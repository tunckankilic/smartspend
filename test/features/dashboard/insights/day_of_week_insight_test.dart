import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/day_of_week_insight.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';

DashboardSnapshot _snap(Map<int, int> byWeekday) {
  return DashboardSnapshot(
    currency: 'TRY',
    currentTotalMinor: 0,
    previousTotalMinor: 0,
    byCategoryCurrent: const <int, int>{},
    byCategoryPrevious: const <int, int>{},
    dailyTotals: const <DateTime, int>{},
    recentExpenses: const <Expense>[],
    topCategoryId: null,
    expenseCount: 0,
    byWeekdayMinor: byWeekday,
  );
}

void main() {
  group('DayOfWeekInsightEvaluator.evaluate', () {
    test('returns null when fewer than two days appeared', () {
      expect(
        DayOfWeekInsightEvaluator.evaluate(
          _snap(<int, int>{DateTime.friday: 50000}),
        ),
        isNull,
      );
    });

    test('returns null when max day is below the 30% threshold', () {
      final r = DayOfWeekInsightEvaluator.evaluate(
        _snap(<int, int>{
          DateTime.monday: 10000,
          DateTime.tuesday: 11000,
          DateTime.wednesday: 12000, // max within 20% of mean
        }),
      );
      expect(r, isNull);
    });

    test('fires when Friday is meaningfully above the mean', () {
      final r = DayOfWeekInsightEvaluator.evaluate(
        _snap(<int, int>{
          DateTime.monday: 10000,
          DateTime.tuesday: 10000,
          DateTime.wednesday: 10000,
          DateTime.thursday: 10000,
          DateTime.friday: 30000, // mean=14000 → delta ≈ +114%
        }),
      );
      expect(r, isNotNull);
      expect(r!.weekday, DateTime.friday);
      expect(r.deltaPercent, greaterThan(30));
    });
  });
}
