import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';

void main() {
  group('DashboardPeriod.thisMonth', () {
    test('should resolve to first → first-of-next at UTC midnight', () {
      final DateTime now = DateTime.utc(2026, 3, 17, 14);
      final DateRange r = const DashboardPeriod.thisMonth().resolve(now);
      expect(r.start, DateTime.utc(2026, 3));
      expect(r.endExclusive, DateTime.utc(2026, 4));
    });

    test('should resolve previous to the prior month-length window', () {
      final DateTime now = DateTime.utc(2026, 3, 17, 14);
      final DateRange r =
          const DashboardPeriod.thisMonth().resolvePrevious(now);
      expect(r.endExclusive, DateTime.utc(2026, 3));
      expect(r.start, DateTime.utc(2026, 3).subtract(const Duration(days: 31)));
    });
  });

  group('DashboardPeriod.thisWeek', () {
    test('should anchor the week on Monday and end the next Monday', () {
      // 2026-05-27 is a Wednesday.
      final DateTime now = DateTime.utc(2026, 5, 27, 9, 30);
      final DateRange r = const DashboardPeriod.thisWeek().resolve(now);
      expect(r.start, DateTime.utc(2026, 5, 25));
      expect(r.endExclusive, DateTime.utc(2026, 6));
    });

    test('previous week should be exactly 7 days before the current start',
        () {
      final DateTime now = DateTime.utc(2026, 5, 27);
      final DateRange r =
          const DashboardPeriod.thisWeek().resolvePrevious(now);
      expect(r.endExclusive, DateTime.utc(2026, 5, 25));
      expect(r.start, DateTime.utc(2026, 5, 18));
    });
  });

  group('DashboardPeriod.last3Months', () {
    test('should span 90 days ending tomorrow-exclusive', () {
      final DateTime now = DateTime.utc(2026, 4, 10);
      final DateRange r = const DashboardPeriod.last3Months().resolve(now);
      expect(r.endExclusive, DateTime.utc(2026, 4, 11));
      expect(
        r.endExclusive.difference(r.start).inDays,
        90,
      );
    });
  });

  group('DashboardPeriod.custom', () {
    test('should resolve the from/to into a UTC inclusive-day window', () {
      final DashboardPeriod p = DashboardPeriod.custom(
        from: DateTime(2026, 5),
        to: DateTime(2026, 5, 7),
      );
      final DateRange r = p.resolve(DateTime.utc(2026, 5, 27));
      expect(r.start, DateTime.utc(2026, 5));
      expect(r.endExclusive, DateTime.utc(2026, 5, 8));
    });

    test('previous window should be the same length, immediately prior', () {
      final DashboardPeriod p = DashboardPeriod.custom(
        from: DateTime(2026, 5),
        to: DateTime(2026, 5, 7),
      );
      final DateRange prev = p.resolvePrevious(DateTime.utc(2026, 5, 27));
      expect(prev.endExclusive, DateTime.utc(2026, 5));
      expect(
        prev.endExclusive.difference(prev.start).inDays,
        7,
      );
    });
  });

  group('DateRange.toFilter', () {
    test('should produce a filter with the right inclusive upper bound', () {
      final DateRange r = DateRange(
        start: DateTime.utc(2026, 5),
        endExclusive: DateTime.utc(2026, 6),
      );
      final filter = r.toFilter();
      expect(filter.dateFrom, DateTime.utc(2026, 5));
      // dateTo is endExclusive − 1µs so half-open semantics hold against
      // the repository's BETWEEN-style range query.
      expect(
        filter.dateTo,
        DateTime.utc(2026, 6).subtract(const Duration(microseconds: 1)),
      );
    });
  });
}
