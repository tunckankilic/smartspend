import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';

/// "You're well under your X budget" — celebratory nudge late in the
/// window when the user is comfortably below the cap.
///
/// Fires only when:
///   * the budget is `healthy` (< 50 % spent),
///   * the current period is at least 70 % elapsed,
///   * `percentSpent + cushion ≤ percentElapsed` (i.e. they're actually
///     pacing under what they'd typically have spent by now).
class BudgetAchievementInsightEvaluator {
  const BudgetAchievementInsightEvaluator._();

  /// Minimum elapsed window fraction before a "you stayed under!"
  /// nudge makes sense.
  static const double minElapsedFraction = 0.70;

  static BudgetAchievementInsight? evaluate({
    required List<BudgetSnapshot> snapshots,
    required DateTime now,
  }) {
    BudgetSnapshot? best;
    double bestCushion = 0;
    for (final BudgetSnapshot s in snapshots) {
      if (s.status.tone != BudgetTone.healthy) continue;
      final double elapsed = _percentElapsed(s, now);
      if (elapsed < minElapsedFraction) continue;
      // "Under-pacing" cushion — positive when the user is below the
      // pro-rata line.
      final double cushion = elapsed - s.status.percentSpent;
      if (cushion <= 0) continue;
      if (best == null || cushion > bestCushion) {
        best = s;
        bestCushion = cushion;
      }
    }
    if (best == null) return null;
    final double elapsed = _percentElapsed(best, now);
    return BudgetAchievementInsight(
      budgetId: best.budget.id,
      categoryId: best.budget.categoryId,
      percentElapsed: (elapsed * 100).round(),
      percentSpent: (best.status.percentSpent * 100).round(),
    );
  }

  static double _percentElapsed(BudgetSnapshot s, DateTime now) {
    final DateTime nowUtc = now.toUtc();
    final Duration total =
        s.window.endUtcExclusive.difference(s.window.startUtc);
    if (total.inSeconds <= 0) return 0;
    final Duration elapsed = nowUtc.difference(s.window.startUtc);
    final double fraction = elapsed.inSeconds / total.inSeconds;
    if (fraction < 0) return 0;
    if (fraction > 1) return 1;
    return fraction;
  }
}
