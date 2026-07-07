import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';

/// Equality + tone contracts for the sealed [DashboardInsight] family.
/// The banner widget switches on the concrete subtype; the bloc dedupes
/// re-emissions via Equatable, so props must cover every field.
void main() {
  group('CategorySpikeInsight', () {
    test('should compare by category and delta', () {
      expect(
        const CategorySpikeInsight(categoryId: 2, deltaPercent: 42),
        const CategorySpikeInsight(categoryId: 2, deltaPercent: 42),
      );
      expect(
        const CategorySpikeInsight(categoryId: 2, deltaPercent: 42),
        isNot(const CategorySpikeInsight(categoryId: 2, deltaPercent: 43)),
      );
    });

    test('should default to the warning tone', () {
      expect(
        const CategorySpikeInsight(categoryId: 2, deltaPercent: 42).tone,
        DashboardInsightTone.warning,
      );
    });
  });

  group('BudgetWarningInsight', () {
    test('should compare by budget, category and percent', () {
      expect(
        const BudgetWarningInsight(budgetId: 1, percentSpent: 85),
        const BudgetWarningInsight(budgetId: 1, percentSpent: 85),
      );
      expect(
        const BudgetWarningInsight(budgetId: 1, percentSpent: 85),
        isNot(
          const BudgetWarningInsight(
            budgetId: 1,
            percentSpent: 85,
            categoryId: 2,
          ),
        ),
      );
    });

    test('should report isExceeded only at or above 100 percent', () {
      expect(
        const BudgetWarningInsight(budgetId: 1, percentSpent: 99).isExceeded,
        isFalse,
      );
      expect(
        const BudgetWarningInsight(budgetId: 1, percentSpent: 100).isExceeded,
        isTrue,
      );
    });
  });

  group('BudgetAchievementInsight', () {
    test('should compare by budget and both percentages', () {
      expect(
        const BudgetAchievementInsight(
          budgetId: 1,
          percentElapsed: 80,
          percentSpent: 40,
        ),
        const BudgetAchievementInsight(
          budgetId: 1,
          percentElapsed: 80,
          percentSpent: 40,
        ),
      );
      expect(
        const BudgetAchievementInsight(
          budgetId: 1,
          percentElapsed: 80,
          percentSpent: 40,
        ).tone,
        DashboardInsightTone.positive,
      );
    });
  });

  group('FrequencyInsight', () {
    test('should compare by tag, count and total', () {
      expect(
        const FrequencyInsight(tag: 'kahve', count: 6, totalMinor: 54000),
        const FrequencyInsight(tag: 'kahve', count: 6, totalMinor: 54000),
      );
      expect(
        const FrequencyInsight(tag: 'kahve', count: 6, totalMinor: 54000),
        isNot(
          const FrequencyInsight(tag: 'kahve', count: 7, totalMinor: 54000),
        ),
      );
      expect(
        const FrequencyInsight(tag: 'kahve', count: 6, totalMinor: 54000).tone,
        DashboardInsightTone.info,
      );
    });
  });

  group('DayOfWeekInsight', () {
    test('should compare by weekday and delta', () {
      expect(
        const DayOfWeekInsight(weekday: 5, deltaPercent: 35),
        const DayOfWeekInsight(weekday: 5, deltaPercent: 35),
      );
      expect(
        const DayOfWeekInsight(weekday: 5, deltaPercent: 35),
        isNot(const DayOfWeekInsight(weekday: 6, deltaPercent: 35)),
      );
      expect(
        const DayOfWeekInsight(weekday: 5, deltaPercent: 35).tone,
        DashboardInsightTone.info,
      );
    });
  });
}
