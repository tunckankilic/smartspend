import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/frequency_insight.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';

DashboardSnapshot _snap(Map<String, TagFrequencyAggregate> tags) {
  return DashboardSnapshot(
    currency: 'TRY',
    currentTotalMinor: 0,
    previousTotalMinor: 0,
    byCategoryCurrent: const <int, int>{},
    byCategoryPrevious: const <int, int>{},
    dailyTotals: const <DateTime, int>{},
    recentExpenses: const <Expense>[],
    topCategoryId: null,
    expenseCount: 0,
    tagFrequency: tags,
  );
}

void main() {
  group('FrequencyInsightEvaluator.evaluate', () {
    test('returns null when no tag hits the minimum count', () {
      expect(
        FrequencyInsightEvaluator.evaluate(_snap(<String,
            TagFrequencyAggregate>{
          'kahve': const TagFrequencyAggregate(count: 4, totalMinor: 1000),
        })),
        isNull,
      );
    });

    test('returns the tag with the highest count', () {
      final r = FrequencyInsightEvaluator.evaluate(
        _snap(<String, TagFrequencyAggregate>{
          'kahve': const TagFrequencyAggregate(count: 15, totalMinor: 67500),
          'kitap': const TagFrequencyAggregate(count: 5, totalMinor: 9000),
        }),
      );
      expect(r, isNotNull);
      expect(r!.tag, 'kahve');
      expect(r.count, 15);
      expect(r.totalMinor, 67500);
    });

    test('ties on count break by total spend', () {
      final r = FrequencyInsightEvaluator.evaluate(
        _snap(<String, TagFrequencyAggregate>{
          'kahve': const TagFrequencyAggregate(count: 7, totalMinor: 10000),
          'çay': const TagFrequencyAggregate(count: 7, totalMinor: 20000),
        }),
      );
      expect(r!.tag, 'çay');
    });
  });
}
