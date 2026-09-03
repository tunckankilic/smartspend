import 'package:timezone/timezone.dart' as tz;

import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_reminder.dart';

/// Hour of the market's morning a reminder fires.
///
/// 09:00 rather than midnight: a deadline notification that arrives while the
/// phone is face-down on a bedside table has been delivered and not received.
const int kTaxReminderHour = 9;

/// Most reminders to hold at once.
///
/// 🚨 iOS caps *pending* local notifications at 64 per app, silently dropping
/// the rest — and the drop is not the ones you would choose. The tax calendar
/// alone can want three leads × two steps × a dozen obligations, which would
/// blow the budget on its own and take the budget alerts and warranty
/// reminders down with it. 48 leaves room for the other three channels, and
/// the planner spends it on the *soonest* deadlines, which are the ones the
/// user can still act on.
const int kMaxTaxReminders = 48;

/// Turns a calendar into the reminders it deserves. Pure.
///
/// Takes the market's [location] rather than reading `tz.local`, because a
/// statutory deadline belongs to the tax authority's calendar and not to
/// wherever the phone is. Every returned [TaxReminder.fireAt] is an absolute
/// UTC instant built from that zone.
///
/// 🚨 AN ITEM WITH NO DEADLINE PRODUCES NOTHING. Today that is most of the
/// calendar — the catalog ships unverified, so most dates are null — and the
/// only correct response is silence. A reminder invented for a date we do not
/// know would be a notification telling someone a deadline they cannot miss
/// is upon them.
List<TaxReminder> planTaxReminders({
  required List<TaxCalendarItem> items,
  required DateTime now,
  required tz.Location location,
  int hour = kTaxReminderHour,
  int maxReminders = kMaxTaxReminders,
}) {
  final DateTime nowUtc = now.toUtc();
  final List<TaxReminder> planned = <TaxReminder>[];

  for (final TaxCalendarItem item in items) {
    // The user said this one does not apply to them. Reminding them anyway
    // is the app arguing with them once a week.
    if (item.dismissedAt != null) {
      continue;
    }

    for (final TaxDeadlineStep step in TaxDeadlineStep.values) {
      final DateTime? due = _dueFor(item, step);
      if (due == null) {
        continue;
      }
      for (final TaxReminderLead lead in TaxReminderLead.values) {
        final DateTime fireAt = _fireAt(
          due: due,
          lead: lead,
          location: location,
          hour: hour,
        );
        // Never fire in the past. `overdue` is not stored anywhere and is not
        // reconstructed here either: a deadline already gone produces no
        // reminder rather than one that arrives late and blames the user.
        if (!fireAt.isAfter(nowUtc)) {
          continue;
        }
        planned.add(
          TaxReminder(
            itemId: item.id,
            kind: item.kind,
            title: item.title,
            step: step,
            lead: lead,
            dueDate: due,
            fireAt: fireAt,
            amountMinor: _amountToName(item),
          ),
        );
      }
    }
  }

  planned.sort((TaxReminder a, TaxReminder b) {
    final int byTime = a.fireAt.compareTo(b.fireAt);
    // Deterministic under equal times, so two runs on the same calendar
    // schedule the same set rather than two arbitrary halves of it.
    if (byTime != 0) {
      return byTime;
    }
    final int byItem = a.itemId.compareTo(b.itemId);
    if (byItem != 0) {
      return byItem;
    }
    return a.step.index.compareTo(b.step.index);
  });

  return planned.length <= maxReminders
      ? planned
      : planned.sublist(0, maxReminders);
}

/// The outstanding deadline for [step], or null when there is nothing to
/// remind about.
///
/// Three separate reasons for null, all of them ordinary: the obligation has
/// no such step (Bağ-Kur is never declared), the rule is unconfirmed so there
/// is no date, or the user has already done it.
DateTime? _dueFor(TaxCalendarItem item, TaxDeadlineStep step) {
  switch (step) {
    case TaxDeadlineStep.declaration:
      if (!item.hasDeclarationStep || item.declaredAt != null) {
        return null;
      }
      return item.declarationDueDate;
    case TaxDeadlineStep.payment:
      if (!item.hasPaymentStep || item.paidAt != null) {
        return null;
      }
      return item.paymentDueDate;
  }
}

/// The amount the notification may name, or null.
///
/// 🚨 Only `accountant`. A number the user typed themselves is a note to self
/// and does not need repeating back to them as if we had checked it; a number
/// from anywhere else does not exist, because the app does not calculate tax.
/// In a notification — read on a lock screen, out of context — any figure
/// reads as an amount due.
int? _amountToName(TaxCalendarItem item) =>
    item.amountSource == TaxAmountSource.accountant ? item.amountMinor : null;

/// [lead] days before [due], at [hour] in [location], as an absolute instant.
///
/// Built through [tz.TZDateTime] rather than by subtracting a [Duration] from
/// the UTC date: `days` arithmetic across a DST boundary is off by an hour,
/// and while Turkey has had no DST since 2016, the correctness of a deadline
/// should not rest on that staying true.
DateTime _fireAt({
  required DateTime due,
  required TaxReminderLead lead,
  required tz.Location location,
  required int hour,
}) {
  final tz.TZDateTime local = tz.TZDateTime(
    location,
    due.year,
    due.month,
    due.day - lead.days,
    hour,
  );
  return local.toUtc();
}
