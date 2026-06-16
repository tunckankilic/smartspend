import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/budget_achievement_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/budget_warning_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/category_spike_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/day_of_week_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/frequency_insight.dart';

/// Composes the five Sprint 6 evaluators into a single priority-ordered
/// resolver.
///
/// Priority — first non-null wins:
///   1. budget warning   (most urgent — user might be about to overspend)
///   2. frequency        (concrete behavioural pattern)
///   3. category spike   (Sprint 5's original rule)
///   4. day-of-week      (softer pattern)
///   5. budget achievement (celebratory nudge — only when nothing else fires)
///
/// Pure function: all five evaluators are pure, the composer just picks
/// among them.
class DashboardInsightPipeline {
  const DashboardInsightPipeline._();

  static DashboardInsight? resolve({
    required DashboardSnapshot snapshot,
    required List<BudgetSnapshot> budgets,
    required DateTime now,
  }) {
    final DashboardInsight? warning =
        BudgetWarningInsightEvaluator.evaluate(budgets);
    if (warning != null) return warning;

    final DashboardInsight? frequency =
        FrequencyInsightEvaluator.evaluate(snapshot);
    if (frequency != null) return frequency;

    final DashboardInsight? spike =
        CategorySpikeInsightEvaluator.evaluate(snapshot);
    if (spike != null) return spike;

    final DashboardInsight? dayOfWeek =
        DayOfWeekInsightEvaluator.evaluate(snapshot);
    if (dayOfWeek != null) return dayOfWeek;

    final DashboardInsight? achievement =
        BudgetAchievementInsightEvaluator.evaluate(
      snapshots: budgets,
      now: now,
    );
    return achievement;
  }
}
