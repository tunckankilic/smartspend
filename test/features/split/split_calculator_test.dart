import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/domain/usecases/split_calculator.dart';

void main() {
  const Participant ali = Participant(id: 'p1', name: 'Ali');
  const Participant mehmet = Participant(id: 'p2', name: 'Mehmet');
  const Participant veli = Participant(id: 'p3', name: 'Veli');

  group('SplitCalculator.calculate - edge cases', () {
    test('should return empty map when no participants', () {
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[],
        items: const <SplitItem>[],
        assignments: const <int, List<String>>{},
        type: SplitType.equal,
        totalMinor: 10000,
      );
      expect(totals, isEmpty);
    });

    test('should seed every participant to zero when total is zero', () {
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet],
        items: const <SplitItem>[],
        assignments: const <int, List<String>>{},
        type: SplitType.equal,
        totalMinor: 0,
      );
      expect(totals, <String, int>{'p1': 0, 'p2': 0});
    });
  });

  group('SplitCalculator.calculate - equal split', () {
    test('should divide total evenly across participants', () {
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet, veli],
        items: const <SplitItem>[],
        assignments: const <int, List<String>>{},
        type: SplitType.equal,
        totalMinor: 30000,
      );
      expect(totals.values.reduce((int a, int b) => a + b), 30000);
      expect(totals['p1'], 10000);
      expect(totals['p2'], 10000);
      expect(totals['p3'], 10000);
    });

    test('should give remainder kuruş to the first participants', () {
      // 1000 / 3 = 333 base + 1 cent remainder.
      // First participant absorbs the extra kuruş.
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet, veli],
        items: const <SplitItem>[],
        assignments: const <int, List<String>>{},
        type: SplitType.equal,
        totalMinor: 1000,
      );
      expect(totals['p1'], 334);
      expect(totals['p2'], 333);
      expect(totals['p3'], 333);
      expect(totals.values.reduce((int a, int b) => a + b), 1000);
    });

    test('should ignore item assignments in equal mode', () {
      // Even with explicit assignments the calculator divides equally.
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet],
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'Kahve', totalPriceMinor: 8000),
        ],
        assignments: const <int, List<String>>{
          1: <String>['p1'], // assigned only to Ali
        },
        type: SplitType.equal,
        totalMinor: 8000,
      );
      expect(totals['p1'], 4000);
      expect(totals['p2'], 4000);
    });
  });

  group('SplitCalculator.calculate - custom split', () {
    test('should allocate single-assignee items wholly to that person', () {
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet],
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'Pizza', totalPriceMinor: 12000),
          SplitItem(id: 2, name: 'Cola', totalPriceMinor: 3000),
        ],
        assignments: const <int, List<String>>{
          1: <String>['p1'],
          2: <String>['p2'],
        },
        type: SplitType.custom,
        totalMinor: 15000,
      );
      expect(totals['p1'], 12000);
      expect(totals['p2'], 3000);
    });

    test('should divide multi-assignee items between assignees', () {
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet, veli],
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'Pizza', totalPriceMinor: 9000),
        ],
        assignments: const <int, List<String>>{
          1: <String>['p1', 'p2'], // Ali + Mehmet share it.
        },
        type: SplitType.custom,
        totalMinor: 9000,
      );
      expect(totals['p1'], 4500);
      expect(totals['p2'], 4500);
      expect(totals['p3'], 0);
    });

    test('should share unassigned items across all participants', () {
      // Bread/table-side items not tagged go to everyone.
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet],
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'Ekmek', totalPriceMinor: 4000),
          SplitItem(id: 2, name: 'Et', totalPriceMinor: 20000),
        ],
        assignments: const <int, List<String>>{
          2: <String>['p1'], // Only the et is tagged.
        },
        type: SplitType.custom,
        totalMinor: 24000,
      );
      // Ekmek 4000 / 2 = 2000 each. Et 20000 → Ali. Totals: Ali 22000,
      // Mehmet 2000.
      expect(totals['p1'], 22000);
      expect(totals['p2'], 2000);
    });

    test('should round multi-assignee remainders deterministically', () {
      // 100 kuruş across 3 assignees → 34, 33, 33 (first absorbs).
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet, veli],
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'Çay', totalPriceMinor: 100),
        ],
        assignments: const <int, List<String>>{
          1: <String>['p1', 'p2', 'p3'],
        },
        type: SplitType.custom,
        totalMinor: 100,
      );
      expect(totals['p1'], 34);
      expect(totals['p2'], 33);
      expect(totals['p3'], 33);
    });

    test('should drop assignments referencing missing participants', () {
      // Stale assignment to a removed participant ("p99") falls back to
      // "shared across remaining" semantics for that item.
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet],
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'Burger', totalPriceMinor: 6000),
        ],
        assignments: const <int, List<String>>{
          1: <String>['p99'],
        },
        type: SplitType.custom,
        totalMinor: 6000,
      );
      // p99 is filtered → no assignees → item shared across all.
      expect(totals['p1'], 3000);
      expect(totals['p2'], 3000);
    });

    test('should handle all items assigned to a single participant', () {
      final Map<String, int> totals = SplitCalculator.calculate(
        participants: const <Participant>[ali, mehmet],
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'A', totalPriceMinor: 1000),
          SplitItem(id: 2, name: 'B', totalPriceMinor: 2000),
        ],
        assignments: const <int, List<String>>{
          1: <String>['p1'],
          2: <String>['p1'],
        },
        type: SplitType.custom,
        totalMinor: 3000,
      );
      expect(totals['p1'], 3000);
      expect(totals['p2'], 0);
    });
  });
}
