import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/insight_pipeline.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';

BudgetSnapshot _budget(int id, int spent, int amount) {
  return BudgetSnapshot(
    budget: Budget(
      id: id,
      amountMinor: amount,
      period: BudgetPeriod.monthly,
      startDate: DateTime.utc(2026, 5, 1),
      isActive: true,
    ),
    window: BudgetWindow(
      startUtc: DateTime.utc(2026, 5, 1),
      endUtcExclusive: DateTime.utc(2026, 6, 1),
    ),
    status: BudgetStatusCalculator.calculate(
      spentMinor: spent,
      amountMinor: amount,
    ),
  );
}

DashboardSnapshot _dash({
  Map<int, int> categoryCurrent = const <int, int>{},
  Map<int, int> categoryPrevious = const <int, int>{},
  Map<String, TagFrequencyAggregate> tags =
      const <String, TagFrequencyAggregate>{},
  Map<int, int> byWeekday = const <int, int>{},
}) {
  return DashboardSnapshot(
    currency: 'TRY',
    currentTotalMinor: categoryCurrent.values.fold(0, (a, b) => a + b),
    previousTotalMinor: categoryPrevious.values.fold(0, (a, b) => a + b),
    byCategoryCurrent: categoryCurrent,
    byCategoryPrevious: categoryPrevious,
    dailyTotals: const <DateTime, int>{},
    recentExpenses: const <Expense>[],
    topCategoryId: categoryCurrent.isEmpty ? null : categoryCurrent.keys.first,
    expenseCount: categoryCurrent.length,
    tagFrequency: tags,
    byWeekdayMinor: byWeekday,
  );
}

void main() {
  group('DashboardInsightPipeline.resolve priority', () {
    test('budget warning wins over a category spike', () {
      final DashboardInsight? r = DashboardInsightPipeline.resolve(
        snapshot: _dash(
          categoryCurrent: <int, int>{1: 20000},
          categoryPrevious: <int, int>{1: 10000},
        ),
        budgets: <BudgetSnapshot>[_budget(7, 900, 1000)], // 90 %
        now: DateTime.utc(2026, 5, 20),
      );
      expect(r, isA<BudgetWarningInsight>());
    });

    test('frequency wins over a category spike', () {
      final DashboardInsight? r = DashboardInsightPipeline.resolve(
        snapshot: _dash(
          categoryCurrent: <int, int>{1: 20000},
          categoryPrevious: <int, int>{1: 10000},
          tags: <String, TagFrequencyAggregate>{
            'kahve': const TagFrequencyAggregate(count: 12, totalMinor: 50000),
          },
        ),
        budgets: const <BudgetSnapshot>[],
        now: DateTime.utc(2026, 5, 20),
      );
      expect(r, isA<FrequencyInsight>());
    });

    test('achievement fires only when no other rule matched', () {
      final DashboardInsight? r = DashboardInsightPipeline.resolve(
        snapshot: _dash(),
        budgets: <BudgetSnapshot>[_budget(3, 300, 1000)],
        now: DateTime.utc(2026, 5, 24), // late in window
      );
      expect(r, isA<BudgetAchievementInsight>());
    });
  });
}
