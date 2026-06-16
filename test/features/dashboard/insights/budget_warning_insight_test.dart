import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/budget_warning_insight.dart';

BudgetSnapshot _snap({
  required int id,
  required int spent,
  required int amount,
  int? categoryId,
}) {
  return BudgetSnapshot(
    budget: Budget(
      id: id,
      amountMinor: amount,
      period: BudgetPeriod.monthly,
      startDate: DateTime.utc(2026, 5, 1),
      isActive: true,
      categoryId: categoryId,
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

void main() {
  group('BudgetWarningInsightEvaluator', () {
    test('returns null when nothing crosses danger', () {
      final BudgetWarningInsight? r =
          BudgetWarningInsightEvaluator.evaluate(<BudgetSnapshot>[
        _snap(id: 1, spent: 100, amount: 1000), // 10 %
        _snap(id: 2, spent: 600, amount: 1000), // 60 % — warning, not danger
      ]);
      expect(r, isNull);
    });

    test('returns the highest-percent danger snapshot', () {
      final BudgetWarningInsight? r =
          BudgetWarningInsightEvaluator.evaluate(<BudgetSnapshot>[
        _snap(id: 1, spent: 810, amount: 1000), // 81 %
        _snap(id: 2, spent: 950, amount: 1000), // 95 %
      ]);
      expect(r, isNotNull);
      expect(r!.budgetId, 2);
      expect(r.percentSpent, 95);
      expect(r.isExceeded, isFalse);
      expect(r.tone, DashboardInsightTone.warning);
    });

    test('prefers exceeded over danger even at lower percent', () {
      final BudgetWarningInsight? r =
          BudgetWarningInsightEvaluator.evaluate(<BudgetSnapshot>[
        _snap(id: 1, spent: 999, amount: 1000), // 99.9 % — danger
        _snap(id: 2, spent: 1010, amount: 1000), // 101 % — exceeded
      ]);
      expect(r, isNotNull);
      expect(r!.budgetId, 2);
      expect(r.isExceeded, isTrue);
    });

    test('ties break by lower budget id for determinism', () {
      final BudgetWarningInsight? r =
          BudgetWarningInsightEvaluator.evaluate(<BudgetSnapshot>[
        _snap(id: 5, spent: 850, amount: 1000),
        _snap(id: 2, spent: 850, amount: 1000),
      ]);
      expect(r!.budgetId, 2);
    });
  });
}
