// The private `_weeklyWindow` / `_monthlyWindow` / `_yearlyWindow` helpers
// are computation routines, not constructors — wrapping them as
// `BudgetWindow._weekly(...)` factories would suggest the existence of a
// "weekly window" type, which is not the modelling intent.
// ignore_for_file: prefer_constructors_over_static_methods

import 'package:equatable/equatable.dart';

import 'package:smartspend/features/budget/domain/entities/budget_period.dart';

/// Half-open `[start, end)` window in UTC that defines "the current
/// budget cycle" for a given budget.
///
/// All boundary instants are normalized to midnight UTC so that summing
/// expenses against the window with `>= start && < end` matches the
/// human intuition of "this Monday through next Monday".
class BudgetWindow extends Equatable {
  const BudgetWindow({
    required this.startUtc,
    required this.endUtcExclusive,
  });

  final DateTime startUtc;
  final DateTime endUtcExclusive;

  /// Inclusive `startUtc`, exclusive `endUtcExclusive`.
  bool contains(DateTime instant) {
    final DateTime utc = instant.toUtc();
    return !utc.isBefore(startUtc) && utc.isBefore(endUtcExclusive);
  }

  Duration get length => endUtcExclusive.difference(startUtc);

  /// Computes the window currently containing [now], anchored at
  /// [startDate].
  ///
  /// * **weekly** — 7-day blocks counting from `startDate`. Stable across
  ///   timezones because we operate on UTC dates only.
  /// * **monthly** — calendar month starting at the same day-of-month as
  ///   `startDate`. If a target month has fewer days (e.g. Feb 28), the
  ///   anchor is clamped to the last day so the window length stays at
  ///   exactly one calendar month.
  /// * **yearly** — calendar year anchored to `startDate.month/day`. Leap
  ///   year edge case (Feb 29) is clamped to Feb 28 in non-leap years.
  ///
  /// If [now] is before [startDate], returns the first window starting
  /// at `startDate`.
  static BudgetWindow current({
    required BudgetPeriod period,
    required DateTime startDate,
    required DateTime now,
  }) {
    final DateTime startAnchor = DateTime.utc(
      startDate.toUtc().year,
      startDate.toUtc().month,
      startDate.toUtc().day,
    );
    final DateTime nowDay = DateTime.utc(
      now.toUtc().year,
      now.toUtc().month,
      now.toUtc().day,
    );
    switch (period) {
      case BudgetPeriod.weekly:
        return _weeklyWindow(startAnchor, nowDay);
      case BudgetPeriod.monthly:
        return _monthlyWindow(startAnchor, nowDay);
      case BudgetPeriod.yearly:
        return _yearlyWindow(startAnchor, nowDay);
    }
  }

  static BudgetWindow _weeklyWindow(DateTime start, DateTime now) {
    final int daysSinceStart = now.difference(start).inDays;
    if (daysSinceStart < 0) {
      return BudgetWindow(
        startUtc: start,
        endUtcExclusive: start.add(const Duration(days: 7)),
      );
    }
    final int weeksSinceStart = daysSinceStart ~/ 7;
    final DateTime windowStart =
        start.add(Duration(days: weeksSinceStart * 7));
    return BudgetWindow(
      startUtc: windowStart,
      endUtcExclusive: windowStart.add(const Duration(days: 7)),
    );
  }

  static BudgetWindow _monthlyWindow(DateTime start, DateTime now) {
    final int anchorDay = start.day;
    if (now.isBefore(start)) {
      return BudgetWindow(
        startUtc: start,
        endUtcExclusive: _monthAnchor(
          year: start.year,
          month: start.month + 1,
          day: anchorDay,
        ),
      );
    }
    DateTime windowStart = _monthAnchor(
      year: now.year,
      month: now.month,
      day: anchorDay,
    );
    if (windowStart.isAfter(now)) {
      // This month's anchor hasn't happened yet — roll back one month.
      windowStart = _monthAnchor(
        year: now.year,
        month: now.month - 1,
        day: anchorDay,
      );
    }
    final DateTime windowEnd = _monthAnchor(
      year: windowStart.year,
      month: windowStart.month + 1,
      day: anchorDay,
    );
    return BudgetWindow(startUtc: windowStart, endUtcExclusive: windowEnd);
  }

  static BudgetWindow _yearlyWindow(DateTime start, DateTime now) {
    if (now.isBefore(start)) {
      return BudgetWindow(
        startUtc: start,
        endUtcExclusive: _monthAnchor(
          year: start.year + 1,
          month: start.month,
          day: start.day,
        ),
      );
    }
    DateTime windowStart = _monthAnchor(
      year: now.year,
      month: start.month,
      day: start.day,
    );
    if (windowStart.isAfter(now)) {
      windowStart = _monthAnchor(
        year: now.year - 1,
        month: start.month,
        day: start.day,
      );
    }
    final DateTime windowEnd = _monthAnchor(
      year: windowStart.year + 1,
      month: start.month,
      day: start.day,
    );
    return BudgetWindow(startUtc: windowStart, endUtcExclusive: windowEnd);
  }

  /// Constructs a UTC midnight with rollover normalization + day-clamping.
  ///
  /// `month=0` or `month=13` rolls over into the adjacent year so callers
  /// can pass `month + 1` / `month - 1` without manual handling.
  /// `day` is clamped to the target month's last day so anchors of 31
  /// don't silently spill into the following month.
  static DateTime _monthAnchor({
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
    final int lastDayOfMonth =
        DateTime.utc(normYear, normMonth + 1, 0).day;
    final int clampedDay = day > lastDayOfMonth ? lastDayOfMonth : day;
    return DateTime.utc(normYear, normMonth, clampedDay);
  }

  @override
  List<Object?> get props => <Object?>[startUtc, endUtcExclusive];
}
