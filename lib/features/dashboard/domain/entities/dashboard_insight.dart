import 'package:equatable/equatable.dart';

/// Banner payload surfaced above the recent-expenses list when one of
/// the rule engine evaluators fires.
///
/// Sealed in Sprint 6 — Sprint 5 shipped only the category-spike rule
/// (now [CategorySpikeInsight]); the budget feature adds four more.
/// The widget switches on the concrete subtype and renders the matching
/// l10n template + drilldown destination.
sealed class DashboardInsight extends Equatable {
  const DashboardInsight({required this.tone});

  final DashboardInsightTone tone;

  @override
  List<Object?> get props => <Object?>[tone];
}

enum DashboardInsightTone {
  /// Spending went up notably or a budget warning crossed — orange.
  warning,

  /// Achievement / under-budget — green.
  positive,

  /// Neutral observation (frequency, day-of-week pattern) — blue.
  info,
}

/// Sprint 5's original rule — a category spent ≥ N% more than last
/// period. The category id drives the drilldown into the filtered
/// expense list (`/expenses?categoryId=X`).
final class CategorySpikeInsight extends DashboardInsight {
  const CategorySpikeInsight({
    required this.categoryId,
    required this.deltaPercent,
    super.tone = DashboardInsightTone.warning,
  });

  final int categoryId;

  /// Signed percentage delta vs the previous period (positive = spent
  /// more this period).
  final double deltaPercent;

  @override
  List<Object?> get props =>
      <Object?>[...super.props, categoryId, deltaPercent];
}

/// A budget has crossed the danger threshold (≥ 80 %).
///
/// `categoryId == null` → general / total budget.
final class BudgetWarningInsight extends DashboardInsight {
  const BudgetWarningInsight({
    required this.budgetId,
    required this.percentSpent,
    this.categoryId,
    super.tone = DashboardInsightTone.warning,
  });

  final int budgetId;
  final int? categoryId;

  /// Rounded percent (`0 - inf`). Exceed cases pass `>= 100`.
  final int percentSpent;

  bool get isExceeded => percentSpent >= 100;

  @override
  List<Object?> get props =>
      <Object?>[...super.props, budgetId, categoryId, percentSpent];
}

/// The user is comfortably under a category budget late in its window —
/// a positive nudge. Selected only when no warning fires.
final class BudgetAchievementInsight extends DashboardInsight {
  const BudgetAchievementInsight({
    required this.budgetId,
    required this.percentElapsed,
    required this.percentSpent,
    this.categoryId,
    super.tone = DashboardInsightTone.positive,
  });

  final int budgetId;
  final int? categoryId;
  final int percentElapsed;
  final int percentSpent;

  @override
  List<Object?> get props => <Object?>[
        ...super.props,
        budgetId,
        categoryId,
        percentElapsed,
        percentSpent,
      ];
}

/// "You bought N coffees this month for ₺X" — a tag-level frequency
/// observation. Selected when a single tag fired ≥ 5 times in the
/// current window.
final class FrequencyInsight extends DashboardInsight {
  const FrequencyInsight({
    required this.tag,
    required this.count,
    required this.totalMinor,
    super.tone = DashboardInsightTone.info,
  });

  final String tag;
  final int count;
  final int totalMinor;

  @override
  List<Object?> get props => <Object?>[...super.props, tag, count, totalMinor];
}

/// "Fridays you spend X % more than average" — weekday-level pattern.
/// Selected when the highest weekday is ≥ 30 % above the mean.
final class DayOfWeekInsight extends DashboardInsight {
  const DayOfWeekInsight({
    required this.weekday,
    required this.deltaPercent,
    super.tone = DashboardInsightTone.info,
  });

  /// ISO 8601 weekday (1 = Monday … 7 = Sunday).
  final int weekday;

  /// `(maxDayTotal - meanDayTotal) / meanDayTotal * 100`. Always
  /// positive (we only fire when the day is *above* average).
  final double deltaPercent;

  @override
  List<Object?> get props => <Object?>[...super.props, weekday, deltaPercent];
}
