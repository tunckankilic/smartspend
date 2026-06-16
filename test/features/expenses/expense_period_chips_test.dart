import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_period_chips.dart';

void main() {
  // Wednesday, 10 June 2026 — Monday of that week is 8 June.
  final DateTime now = DateTime(2026, 6, 10, 14, 30);

  group('ExpensePeriodChips.startOf', () {
    test('should return null for the all period', () {
      expect(ExpensePeriodChips.startOf(ExpenseListPeriod.all, now), isNull);
    });

    test('should return Monday midnight for thisWeek', () {
      expect(
        ExpensePeriodChips.startOf(ExpenseListPeriod.thisWeek, now),
        DateTime(2026, 6, 8),
      );
    });

    test('should return the 1st of the month for thisMonth', () {
      expect(
        ExpensePeriodChips.startOf(ExpenseListPeriod.thisMonth, now),
        DateTime(2026, 6),
      );
    });

    test('should return the 1st of two months back for last3Months', () {
      expect(
        ExpensePeriodChips.startOf(ExpenseListPeriod.last3Months, now),
        DateTime(2026, 4),
      );
    });

    test('should roll over the year boundary for last3Months', () {
      final DateTime january = DateTime(2026, 1, 15);
      expect(
        ExpensePeriodChips.startOf(ExpenseListPeriod.last3Months, january),
        DateTime(2025, 11),
      );
    });
  });

  group('ExpensePeriodChips.periodOf', () {
    test('should detect all when the filter has no date bounds', () {
      expect(
        ExpensePeriodChips.periodOf(ExpenseFilter.empty, now),
        ExpenseListPeriod.all,
      );
    });

    test('should detect each preset from its canonical dateFrom', () {
      for (final ExpenseListPeriod p in <ExpenseListPeriod>[
        ExpenseListPeriod.thisWeek,
        ExpenseListPeriod.thisMonth,
        ExpenseListPeriod.last3Months,
      ]) {
        final ExpenseFilter filter = ExpenseFilter(
          dateFrom: ExpensePeriodChips.startOf(p, now),
        );
        expect(ExpensePeriodChips.periodOf(filter, now), p);
      }
    });

    test('should return null for a custom range with an upper bound', () {
      final ExpenseFilter filter = ExpenseFilter(
        dateFrom: DateTime(2026, 6, 8),
        dateTo: DateTime(2026, 6, 9),
      );
      expect(ExpensePeriodChips.periodOf(filter, now), isNull);
    });

    test('should return null for a dateFrom that matches no preset', () {
      final ExpenseFilter filter = ExpenseFilter(
        dateFrom: DateTime(2026, 6, 3),
      );
      expect(ExpensePeriodChips.periodOf(filter, now), isNull);
    });

    test('should keep non-date filters out of the decision', () {
      final ExpenseFilter filter = ExpenseFilter(
        dateFrom: DateTime(2026, 6, 8),
        categoryIds: const <int>{1, 2},
        searchQuery: 'migros',
      );
      expect(
        ExpensePeriodChips.periodOf(filter, now),
        ExpenseListPeriod.thisWeek,
      );
    });
  });
}
