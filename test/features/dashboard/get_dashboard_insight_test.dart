import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_insight.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';

DashboardSnapshot _snap({
  required Map<int, int> current,
  required Map<int, int> previous,
}) {
  return DashboardSnapshot(
    currency: 'TRY',
    currentTotalMinor: current.values.fold(0, (a, b) => a + b),
    previousTotalMinor: previous.values.fold(0, (a, b) => a + b),
    byCategoryCurrent: current,
    byCategoryPrevious: previous,
    dailyTotals: const <DateTime, int>{},
    recentExpenses: const <Expense>[],
    topCategoryId: current.isEmpty ? null : current.keys.first,
    expenseCount: current.length,
  );
}

void main() {
  test('should return null when the period is empty', () {
    final insight = GetDashboardInsightUseCase.evaluate(
      DashboardSnapshot.empty,
    );
    expect(insight, isNull);
  });

  test('should return null when no category crosses the 20% threshold', () {
    final insight = GetDashboardInsightUseCase.evaluate(
      _snap(
        current: <int, int>{1: 12000, 2: 50000},
        previous: <int, int>{1: 11500, 2: 49000},
      ),
    );
    expect(insight, isNull);
  });

  test('should surface the category whose delta crosses the threshold', () {
    final insight = GetDashboardInsightUseCase.evaluate(
      _snap(
        current: <int, int>{1: 20000, 2: 5000},
        previous: <int, int>{1: 10000, 2: 5000},
      ),
    );
    expect(insight, isNotNull);
    expect(insight!.categoryId, 1);
    expect(insight.deltaPercent, closeTo(100, 0.01));
    expect(insight.tone, DashboardInsightTone.warning);
  });

  test('should pick the biggest spike when multiple exceed the threshold',
      () {
    final insight = GetDashboardInsightUseCase.evaluate(
      _snap(
        current: <int, int>{1: 20000, 2: 30000},
        previous: <int, int>{1: 10000, 2: 10000},
      ),
    );
    expect(insight!.categoryId, 2); // 200% beats 100%
  });

  test('should ignore categories below the minimum minor-unit floor', () {
    final insight = GetDashboardInsightUseCase.evaluate(
      _snap(
        current: <int, int>{1: 500}, // ₺5 — below the ₺100 floor
        previous: <int, int>{1: 100},
      ),
    );
    expect(insight, isNull);
  });

  test('should ignore categories that did not exist last period', () {
    final insight = GetDashboardInsightUseCase.evaluate(
      _snap(
        current: <int, int>{1: 50000},
        previous: <int, int>{},
      ),
    );
    expect(insight, isNull);
  });

  test('threshold constant should be 20%', () {
    expect(kInsightSpikeThresholdPercent, 20);
  });
}
