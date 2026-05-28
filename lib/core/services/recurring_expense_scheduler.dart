import 'package:drift/drift.dart' show Value;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';

/// Foreground scheduler that materialises recurring-expense occurrences
/// (Sprint 6 carry-over from Sprint 3.2).
///
/// Design choices:
/// * **Foreground only** — `tick()` runs from `main.dart` at startup and
///   from a 12-hour throttle when the app foregrounds. No background
///   isolate, no platform AlarmManager / BGAppRefreshTask. iOS+Android
///   parity stays simple; cron-grade reliability lands when Sprint 8
///   wires `pg_cron` + a Supabase Edge Function.
/// * **Idempotency via SharedPreferences** rather than a new Drift
///   column — keeps the v2 schema clean. The key
///   `recurring.<templateId>.seq` stores the highest occurrence index
///   already materialised, so a re-run of `tick()` after a crash never
///   duplicates a row.
/// * **Pure helpers exposed** — [occurrencesElapsed] and
///   [occurrenceDate] are top-level so unit tests can hit them without
///   spinning up the scheduler.
abstract class RecurringExpenseScheduler {
  /// Materialise missing occurrences for every recurring template and
  /// schedule a reminder notification 1 day before each next occurrence
  /// within a 30-day horizon.
  ///
  /// Returns the number of expense rows inserted during this tick.
  Future<int> tick();
}

class RecurringExpenseSchedulerImpl implements RecurringExpenseScheduler {
  RecurringExpenseSchedulerImpl({
    required ExpenseDao expenseDao,
    required this.notifications,
    required this.prefs,
    required this.logger,
    DateTime Function()? now,
  })  : _dao = expenseDao,
        _now = now ?? DateTime.now;

  final NotificationService notifications;
  final SharedPreferences prefs;
  final Logger logger;

  static const String _kLastRunKey = 'recurring.scheduler.lastRunMs';

  /// Don't spin up more than twice a day — recurring expenses change
  /// at week/month/year granularity, not at app-foreground granularity.
  static const Duration throttle = Duration(hours: 12);

  /// Skip scheduling reminders for occurrences further out than this.
  /// iOS caps pending local notifications at 64; flooding the queue with
  /// a yearly budget's 10-year horizon would be pointless.
  static const Duration reminderHorizon = Duration(days: 30);

  final ExpenseDao _dao;
  final DateTime Function() _now;

  NotificationService get _notifications => notifications;
  SharedPreferences get _prefs => prefs;
  Logger get _logger => logger;

  @override
  Future<int> tick() async {
    final DateTime nowUtc = _now().toUtc();
    final int lastRunMs = _prefs.getInt(_kLastRunKey) ?? 0;
    if (lastRunMs > 0) {
      final DateTime lastRun = DateTime.fromMillisecondsSinceEpoch(
        lastRunMs,
        isUtc: true,
      );
      if (nowUtc.difference(lastRun) < throttle) {
        return 0;
      }
    }

    final List<drift_db.Expense> templates =
        await _dao.getRecurringTemplates();
    int inserted = 0;
    for (final drift_db.Expense t in templates) {
      inserted += await _materialiseAndSchedule(t, nowUtc);
    }

    await _prefs.setInt(_kLastRunKey, nowUtc.millisecondsSinceEpoch);
    _logger.i(
      'recurring.scheduler tick now=$nowUtc templates=${templates.length} '
      'inserted=$inserted',
    );
    return inserted;
  }

  Future<int> _materialiseAndSchedule(
    drift_db.Expense template,
    DateTime nowUtc,
  ) async {
    final RecurringPeriod? period = RecurringPeriod.fromName(
      template.recurringPeriod,
    );
    if (period == null) {
      // Row marked recurring but with no/invalid period — skip silently
      // so a stale upgrade doesn't crash the scheduler.
      return 0;
    }
    final DateTime anchor = DateTime.utc(
      template.date.year,
      template.date.month,
      template.date.day,
    );

    final int elapsed = occurrencesElapsed(
      period: period,
      anchorUtc: anchor,
      nowUtc: nowUtc,
    );
    final String prefsKey = 'recurring.${template.id}.seq';
    final int lastSeq = _prefs.getInt(prefsKey) ?? 0; // 0 = anchor row.

    int inserted = 0;
    for (int seq = lastSeq + 1; seq <= elapsed; seq++) {
      final DateTime occurrence = occurrenceDate(
        period: period,
        anchorUtc: anchor,
        seq: seq,
      );
      final DateTime stamp = DateTime.now().toUtc();
      await _dao.insertExpense(
        drift_db.ExpensesCompanion.insert(
          amount: template.amount,
          categoryId: template.categoryId,
          date: occurrence,
          isManual: const Value<bool>(false),
          isRecurring: const Value<bool>(false),
          note: Value<String?>(template.note),
          // Sprint 6: receipt link is intentionally NOT carried forward —
          // each occurrence is a fresh row with no underlying receipt.
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      inserted++;
    }
    if (inserted > 0) {
      await _prefs.setInt(prefsKey, elapsed);
    }

    // Reminder for the next future occurrence within the horizon.
    final int nextSeq = elapsed + 1;
    final DateTime nextOccurrence = occurrenceDate(
      period: period,
      anchorUtc: anchor,
      seq: nextSeq,
    );
    final DateTime reminderAt =
        nextOccurrence.subtract(const Duration(days: 1));
    final Duration delay = reminderAt.difference(nowUtc);
    if (delay > Duration.zero && delay <= reminderHorizon) {
      await _notifications.scheduleRecurringReminder(
        id: _notifications.recurringNotificationId(template.id),
        title: 'Upcoming recurring expense',
        body: '${template.note ?? 'Recurring'}: due tomorrow',
        when: reminderAt,
      );
    }
    return inserted;
  }
}

// ---------------------------------------------------------------------------
// Pure helpers — exposed top-level for unit testing.
// ---------------------------------------------------------------------------

/// Number of fully-elapsed occurrences between [anchorUtc] and [nowUtc],
/// using calendar-aware math for monthly + yearly periods.
///
/// `0` means "only the anchor itself has occurred". Negative result is
/// clamped to `0`.
int occurrencesElapsed({
  required RecurringPeriod period,
  required DateTime anchorUtc,
  required DateTime nowUtc,
}) {
  if (nowUtc.isBefore(anchorUtc)) return 0;
  switch (period) {
    case RecurringPeriod.weekly:
      return nowUtc.difference(anchorUtc).inDays ~/ 7;
    case RecurringPeriod.monthly:
      int months = (nowUtc.year - anchorUtc.year) * 12 +
          (nowUtc.month - anchorUtc.month);
      // Clamp the anchor day into `now`'s month before comparing — Jan 31
      // anchor + Feb-28 "now" should still register the Feb 28 occurrence
      // as reached. Without the clamp we'd subtract a month incorrectly.
      final int lastDayOfNowMonth =
          DateTime.utc(nowUtc.year, nowUtc.month + 1, 0).day;
      final int effectiveAnchorDay = anchorUtc.day > lastDayOfNowMonth
          ? lastDayOfNowMonth
          : anchorUtc.day;
      if (nowUtc.day < effectiveAnchorDay) months -= 1;
      return months < 0 ? 0 : months;
    case RecurringPeriod.yearly:
      int years = nowUtc.year - anchorUtc.year;
      // Apply the same clamping logic so a Feb 29 anchor lands on Feb 28
      // in non-leap years without double-decrementing.
      final int lastDayOfTargetMonth =
          DateTime.utc(nowUtc.year, anchorUtc.month + 1, 0).day;
      final int effectiveAnchorDay = anchorUtc.day > lastDayOfTargetMonth
          ? lastDayOfTargetMonth
          : anchorUtc.day;
      if (nowUtc.month < anchorUtc.month ||
          (nowUtc.month == anchorUtc.month &&
              nowUtc.day < effectiveAnchorDay)) {
        years -= 1;
      }
      return years < 0 ? 0 : years;
  }
}

/// Date of occurrence `seq`. `seq == 0` returns the anchor.
///
/// Monthly / yearly anchors clamp the day to the target month's length
/// so a Jan 31 monthly template lands on Feb 28, then Mar 31, etc.
DateTime occurrenceDate({
  required RecurringPeriod period,
  required DateTime anchorUtc,
  required int seq,
}) {
  switch (period) {
    case RecurringPeriod.weekly:
      return anchorUtc.add(Duration(days: 7 * seq));
    case RecurringPeriod.monthly:
      return _monthAnchor(
        year: anchorUtc.year,
        month: anchorUtc.month + seq,
        day: anchorUtc.day,
      );
    case RecurringPeriod.yearly:
      return _monthAnchor(
        year: anchorUtc.year + seq,
        month: anchorUtc.month,
        day: anchorUtc.day,
      );
  }
}

DateTime _monthAnchor({
  required int year,
  required int month,
  required int day,
}) {
  int normYear = year;
  int normMonth = month;
  while (normMonth < 1) {
    normMonth += 12;
    normYear -= 1;
  }
  while (normMonth > 12) {
    normMonth -= 12;
    normYear += 1;
  }
  final int lastDayOfMonth = DateTime.utc(normYear, normMonth + 1, 0).day;
  final int clampedDay = day > lastDayOfMonth ? lastDayOfMonth : day;
  return DateTime.utc(normYear, normMonth, clampedDay);
}
