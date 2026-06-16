import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';

/// Sprint 5's original rule — extracted here in Sprint 6 so the pipeline
/// composer can compose five symmetric evaluators.
class CategorySpikeInsightEvaluator {
  const CategorySpikeInsightEvaluator._();

  /// 20 % spike threshold — matches the Sprint 5 prompt.
  static const double thresholdPercent = 20;

  /// Minimum current-period minor-unit spend before a category is
  /// eligible. Without this, a category that jumped from ₺1 → ₺5
  /// (a 400 % "spike") would dominate the banner.
  static const int minCurrentMinor = 10000; // ₺100 / €100.

  static CategorySpikeInsight? evaluate(DashboardSnapshot snapshot) {
    if (snapshot.isEmpty) return null;
    CategorySpikeInsight? best;
    double bestDelta = thresholdPercent;
    for (final MapEntry<int, int> entry
        in snapshot.byCategoryCurrent.entries) {
      final int currentMinor = entry.value;
      if (currentMinor < minCurrentMinor) continue;
      final int previousMinor = snapshot.byCategoryPrevious[entry.key] ?? 0;
      if (previousMinor == 0) continue;
      final double delta =
          ((currentMinor - previousMinor) / previousMinor) * 100.0;
      if (delta >= bestDelta) {
        bestDelta = delta;
        best = CategorySpikeInsight(
          categoryId: entry.key,
          deltaPercent: delta,
        );
      }
    }
    return best;
  }
}
