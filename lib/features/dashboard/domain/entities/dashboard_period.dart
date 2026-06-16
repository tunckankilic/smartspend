import 'package:equatable/equatable.dart';

import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';

/// User-selectable date windows for the dashboard.
///
/// Each preset resolves to an [ExpenseFilter] whose `[dateFrom, dateTo]`
/// half-open interval `[start, endExclusive)` selects the *current*
/// period; the same window length immediately preceding it is the
/// *previous* period used for delta comparison.
///
/// Custom windows carry their own `[from, to]` and use a previous window
/// of identical length ending at `from`.
sealed class DashboardPeriod extends Equatable {
  const DashboardPeriod();

  /// Sentinel: this month, 1st 00:00 → next month 1st 00:00.
  const factory DashboardPeriod.thisMonth() = ThisMonthPeriod;

  /// Sentinel: this week, Monday 00:00 → next Monday 00:00.
  const factory DashboardPeriod.thisWeek() = ThisWeekPeriod;

  /// Sentinel: 90 days ending at `now`.
  const factory DashboardPeriod.last3Months() = Last3MonthsPeriod;

  /// Explicit window. `from` inclusive, `to` exclusive (UTC midnight).
  const factory DashboardPeriod.custom({
    required DateTime from,
    required DateTime to,
  }) = CustomPeriod;

  /// Resolve to a `[start, endExclusive)` UTC range against [now].
  DateRange resolve(DateTime now);

  /// Mirror of [resolve] for the period immediately before the current
  /// one. Same length, ending at the current start.
  DateRange resolvePrevious(DateTime now) {
    final DateRange current = resolve(now);
    final Duration length = current.endExclusive.difference(current.start);
    return DateRange(
      start: current.start.subtract(length),
      endExclusive: current.start,
    );
  }
}

final class ThisMonthPeriod extends DashboardPeriod {
  const ThisMonthPeriod();

  @override
  DateRange resolve(DateTime now) {
    final DateTime u = now.toUtc();
    final DateTime start = DateTime.utc(u.year, u.month);
    final DateTime end = DateTime.utc(u.year, u.month + 1);
    return DateRange(start: start, endExclusive: end);
  }

  @override
  List<Object?> get props => const <Object?>[];
}

final class ThisWeekPeriod extends DashboardPeriod {
  const ThisWeekPeriod();

  @override
  DateRange resolve(DateTime now) {
    final DateTime u = now.toUtc();
    final DateTime day = DateTime.utc(u.year, u.month, u.day);
    // Dart's weekday: Mon=1..Sun=7. Anchor weeks on Monday.
    final DateTime start = day.subtract(Duration(days: day.weekday - 1));
    return DateRange(
      start: start,
      endExclusive: start.add(const Duration(days: 7)),
    );
  }

  @override
  List<Object?> get props => const <Object?>[];
}

final class Last3MonthsPeriod extends DashboardPeriod {
  const Last3MonthsPeriod();

  @override
  DateRange resolve(DateTime now) {
    final DateTime u = now.toUtc();
    final DateTime endExclusive = DateTime.utc(u.year, u.month, u.day)
        .add(const Duration(days: 1));
    final DateTime start = endExclusive.subtract(const Duration(days: 90));
    return DateRange(start: start, endExclusive: endExclusive);
  }

  @override
  List<Object?> get props => const <Object?>[];
}

final class CustomPeriod extends DashboardPeriod {
  const CustomPeriod({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  DateRange resolve(DateTime now) {
    return DateRange(
      start: DateTime.utc(from.year, from.month, from.day),
      endExclusive: DateTime.utc(to.year, to.month, to.day)
          .add(const Duration(days: 1)),
    );
  }

  @override
  List<Object?> get props => <Object?>[from, to];
}

/// Half-open `[start, endExclusive)` UTC date window.
class DateRange extends Equatable {
  const DateRange({required this.start, required this.endExclusive});

  final DateTime start;
  final DateTime endExclusive;

  /// Convert to an [ExpenseFilter] — repository treats `dateTo` as
  /// inclusive, so we subtract one tick to keep the half-open semantics.
  ExpenseFilter toFilter({Set<int>? categoryIds}) {
    return ExpenseFilter(
      dateFrom: start,
      dateTo: endExclusive.subtract(const Duration(microseconds: 1)),
      categoryIds: categoryIds ?? const <int>{},
    );
  }

  @override
  List<Object?> get props => <Object?>[start, endExclusive];
}
