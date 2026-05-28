import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';

/// Picks the most concerning budget snapshot (≥ 80 %) and emits a
/// [BudgetWarningInsight] for it.
///
/// Pure function: no IO, no clock. Tie-breaker order:
///   1. exceeded > danger,
///   2. higher percent first,
///   3. lower budget id (deterministic for tests).
class BudgetWarningInsightEvaluator {
  const BudgetWarningInsightEvaluator._();

  static BudgetWarningInsight? evaluate(List<BudgetSnapshot> snapshots) {
    BudgetSnapshot? best;
    for (final BudgetSnapshot s in snapshots) {
      final BudgetTone tone = s.status.tone;
      if (tone != BudgetTone.danger && tone != BudgetTone.exceeded) continue;
      if (best == null) {
        best = s;
        continue;
      }
      // Exceeded always wins over danger.
      if (s.status.isExceeded && !best.status.isExceeded) {
        best = s;
        continue;
      }
      if (!s.status.isExceeded && best.status.isExceeded) continue;
      // Same tone class — pick higher percent, then lower id.
      if (s.status.percentSpent > best.status.percentSpent) {
        best = s;
      } else if (s.status.percentSpent == best.status.percentSpent &&
          s.budget.id < best.budget.id) {
        best = s;
      }
    }
    if (best == null) return null;
    return BudgetWarningInsight(
      budgetId: best.budget.id,
      categoryId: best.budget.categoryId,
      percentSpent: (best.status.percentSpent * 100).round(),
    );
  }
}
