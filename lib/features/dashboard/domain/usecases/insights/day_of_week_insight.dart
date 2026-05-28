import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';

/// Finds the weekday whose average spending is meaningfully above the
/// overall daily mean.
///
/// Threshold: max-weekday total must be `>= (1 + minDelta) * meanDayTotal`,
/// computed over weekdays that *appeared* in the period (we don't punish
/// weekdays missing from a short window like a 3-day custom range).
class DayOfWeekInsightEvaluator {
  const DayOfWeekInsightEvaluator._();

  /// 30 % above the per-day average is "notable" — matches the prompt's
  /// example copy.
  static const double minDelta = 0.30;

  static DayOfWeekInsight? evaluate(DashboardSnapshot snapshot) {
    final Map<int, int> by = snapshot.byWeekdayMinor;
    if (by.length < 2) return null; // need at least two days to compare.
    final int sum = by.values.fold<int>(0, (int a, int b) => a + b);
    if (sum <= 0) return null;
    final double mean = sum / by.length;
    int? bestDay;
    int bestTotal = 0;
    for (final MapEntry<int, int> entry in by.entries) {
      if (entry.value > bestTotal) {
        bestTotal = entry.value;
        bestDay = entry.key;
      }
    }
    if (bestDay == null || mean <= 0) return null;
    final double delta = (bestTotal - mean) / mean;
    if (delta < minDelta) return null;
    return DayOfWeekInsight(
      weekday: bestDay,
      deltaPercent: delta * 100.0,
    );
  }
}
