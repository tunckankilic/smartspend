// ignore_for_file: prefer_initializing_formals — private field convention,
// matching the rest of core/services.
import 'package:flutter/widgets.dart' show Locale;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:smartspend/core/database/daos/user_settings_dao.dart';
import 'package:smartspend/core/market/market_registry.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_reminder.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';
import 'package:smartspend/features/taxes/domain/tax_reminder_planner.dart';
// Imported for `taxObligationName` only. The file lives under presentation
// because that is where the rest of the label mapping lives, but it is a pure
// l10n lookup with no widgets in it; duplicating its fourteen-branch switch
// here would guarantee the two drift apart the first time a kind is added.
import 'package:smartspend/features/taxes/presentation/tax_labels.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// [UserSettings] key holding a fingerprint of the last plan actually
/// scheduled.
const String kTaxRemindersFingerprintKey = 'tax_reminders.fingerprint';

/// Schedules the tax calendar's deadline reminders.
abstract class TaxReminderScheduler {
  /// Recomputes the plan and makes the device match it.
  ///
  /// Returns how many reminders are now scheduled, or 0 when nothing was
  /// done. Safe and cheap to call often: an unchanged plan is a no-op.
  Future<int> tick({required String languageCode});
}

/// Replaces the whole tax reminder set on every change.
///
/// 🚨 REPLACE, NOT DIFF. The plan is a pure function of the calendar, so
/// recomputing it costs nothing, while tracking which ids were written last
/// time means keeping bookkeeping that can drift out of step with what the OS
/// actually holds. The failure that matters is the stale one: a reminder for a
/// return the user filed last week is the notification that makes someone
/// turn notifications off for good.
class TaxReminderSchedulerImpl implements TaxReminderScheduler {
  TaxReminderSchedulerImpl({
    required TaxRepository repository,
    required NotificationService notifications,
    required MarketRegistry markets,
    required UserSettingsDao settingsDao,
    DateTime Function()? clock,
  })  : _repository = repository,
        _notifications = notifications,
        _markets = markets,
        _settingsDao = settingsDao,
        _now = clock ?? DateTime.now;

  final TaxRepository _repository;
  final NotificationService _notifications;
  final MarketRegistry _markets;
  final UserSettingsDao _settingsDao;
  final DateTime Function() _now;

  @override
  Future<int> tick({required String languageCode}) async {
    // Scheduling into a denied permission writes reminders nobody will ever
    // see and then reports success. Better to do nothing and say so.
    if (!await _notifications.hasPermission()) {
      return 0;
    }

    // Idempotent, and cheap after the first call. Doing it here rather than
    // trusting an earlier initialize() means the scheduler is correct in a
    // test that never built the notification plugin.
    tz_data.initializeTimeZones();

    final TaxCalendarSnapshot snapshot =
        await _repository.watchCalendar().first;
    final List<TaxReminder> plan = planTaxReminders(
      items: snapshot.items,
      now: _now(),
      location: tz.getLocation(_markets.active.timeZone),
    );

    // The language is part of the fingerprint: the same deadlines in a
    // different app language are different notifications, and a user who
    // switches to English should not keep receiving Turkish ones.
    final String fingerprint = _fingerprint(plan, languageCode);
    final String? last =
        await _settingsDao.getValue(kTaxRemindersFingerprintKey);
    if (fingerprint == last) {
      return plan.length;
    }

    await _clearOurRange();

    final AppLocalizations l =
        await AppLocalizations.delegate.load(Locale(languageCode));
    // 🚨 Required, and easy to miss: this scheduler runs from `main()` before
    // `runApp`, so `GlobalMaterialLocalizations` — which is what normally
    // loads intl's date symbols — has not run. Without this, formatting a
    // deadline in any locale but en_US throws, and the whole boot-time tick
    // fails silently inside its `unawaited`.
    await initializeDateFormatting(languageCode);
    for (final TaxReminder reminder in plan) {
      await _notifications.scheduleTaxReminder(
        id: _notifications.taxNotificationId(
          itemId: reminder.itemId,
          stepIndex: reminder.step.index,
          leadIndex: reminder.lead.index,
        ),
        title: _title(l, reminder),
        body: _body(l, reminder, languageCode),
        when: reminder.fireAt,
        payload: 'tax:${reminder.itemId}',
      );
    }

    await _settingsDao.setValue(kTaxRemindersFingerprintKey, fingerprint);
    return plan.length;
  }

  /// Cancels every pending notification in the tax id range.
  ///
  /// By range rather than by remembered id: the OS is the authority on what is
  /// actually pending, and anything of ours still sitting there after this is
  /// a reminder the current calendar no longer justifies.
  Future<void> _clearOurRange() async {
    final List<int> pending = await _notifications.pendingIds();
    for (final int id in pending) {
      if (id >= kTaxNotificationIdStart && id < kTaxNotificationIdEnd) {
        await _notifications.cancel(id);
      }
    }
  }

  String _title(AppLocalizations l, TaxReminder reminder) {
    final String name =
        reminder.title ?? taxObligationName(l, reminder.kind);
    switch (reminder.step) {
      case TaxDeadlineStep.declaration:
        return l.taxReminderTitleDeclaration(name);
      case TaxDeadlineStep.payment:
        return l.taxReminderTitlePayment(name);
    }
  }

  /// 🚨 Never certainty language. Every date in the calendar today comes from
  /// a rule nobody has verified against GİB, so "the deadline is today" would
  /// be a claim the app cannot support — on a lock screen, out of any context
  /// that could qualify it. "By our calendar … confirm it with your
  /// accountant" is the same information without the false authority.
  String _body(AppLocalizations l, TaxReminder reminder, String languageCode) {
    final String date =
        DateFormat.yMMMMd(languageCode).format(reminder.dueDate);
    final String lead = switch (reminder.lead) {
      TaxReminderLead.sevenDays => l.taxReminderBodyWeek(date),
      TaxReminderLead.oneDay => l.taxReminderBodyTomorrow(date),
      TaxReminderLead.dayOf => l.taxReminderBodyToday,
    };

    // The planner has already dropped any amount the accountant did not give,
    // so reaching here means a person with standing said this number.
    final int? amount = reminder.amountMinor;
    if (amount == null) {
      return lead;
    }
    return lead +
        l.taxReminderAmountFromAccountant(
          formatMinor(
            amount,
            _markets.active.currencyCode,
            locale: languageCode,
          ),
        );
  }

  /// A cheap value that changes exactly when the scheduled set should.
  String _fingerprint(List<TaxReminder> plan, String languageCode) {
    final StringBuffer buffer = StringBuffer(languageCode);
    for (final TaxReminder r in plan) {
      buffer
        ..write('|')
        ..write(r.itemId)
        ..write(':')
        ..write(r.step.index)
        ..write(':')
        ..write(r.lead.index)
        ..write(':')
        ..write(r.fireAt.toIso8601String())
        ..write(':')
        ..write(r.amountMinor ?? '');
    }
    return buffer.toString();
  }
}
