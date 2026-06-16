import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';

/// Surfaces a single repeating tag — e.g. "15 coffees, ₺675 this month".
///
/// Selection rule: tag with the highest count, must be at least
/// [minCount] hits. Ties broken by highest total spend, then by tag
/// name (alphabetical) for test determinism.
class FrequencyInsightEvaluator {
  const FrequencyInsightEvaluator._();

  static const int minCount = 5;

  static FrequencyInsight? evaluate(DashboardSnapshot snapshot) {
    if (snapshot.tagFrequency.isEmpty) return null;
    String? bestKey;
    TagFrequencyAggregate? bestVal;
    for (final MapEntry<String, TagFrequencyAggregate> entry
        in snapshot.tagFrequency.entries) {
      if (entry.value.count < minCount) continue;
      if (bestVal == null) {
        bestKey = entry.key;
        bestVal = entry.value;
        continue;
      }
      if (entry.value.count > bestVal.count) {
        bestKey = entry.key;
        bestVal = entry.value;
      } else if (entry.value.count == bestVal.count &&
          entry.value.totalMinor > bestVal.totalMinor) {
        bestKey = entry.key;
        bestVal = entry.value;
      } else if (entry.value.count == bestVal.count &&
          entry.value.totalMinor == bestVal.totalMinor &&
          entry.key.compareTo(bestKey!) < 0) {
        bestKey = entry.key;
        bestVal = entry.value;
      }
    }
    if (bestKey == null || bestVal == null) return null;
    return FrequencyInsight(
      tag: bestKey,
      count: bestVal.count,
      totalMinor: bestVal.totalMinor,
    );
  }
}
