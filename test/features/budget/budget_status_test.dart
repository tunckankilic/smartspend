import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget_status.dart';

void main() {
  group('BudgetStatusCalculator.calculate', () {
    test('should classify under 50% as healthy', () {
      final BudgetStatus s = BudgetStatusCalculator.calculate(
        spentMinor: 4000,
        amountMinor: 10000,
      );
      expect(s.tone, BudgetTone.healthy);
      expect(s.percentSpent, closeTo(0.4, 0.001));
      expect(s.crossedThresholds, isEmpty);
      expect(s.isOnTrack, isTrue);
      expect(s.isExceeded, isFalse);
    });

    test('should classify 50-79% as warning', () {
      final BudgetStatus s = BudgetStatusCalculator.calculate(
        spentMinor: 6000,
        amountMinor: 10000,
      );
      expect(s.tone, BudgetTone.warning);
      expect(s.crossedThresholds, contains(50));
      expect(s.crossedThresholds, isNot(contains(80)));
    });

    test('should classify 80-99% as danger', () {
      final BudgetStatus s = BudgetStatusCalculator.calculate(
        spentMinor: 9000,
        amountMinor: 10000,
      );
      expect(s.tone, BudgetTone.danger);
      expect(s.crossedThresholds, containsAll(<int>[50, 80]));
      expect(s.crossedThresholds, isNot(contains(100)));
    });

    test('should classify >=100% as exceeded with negative remaining', () {
      final BudgetStatus s = BudgetStatusCalculator.calculate(
        spentMinor: 12000,
        amountMinor: 10000,
      );
      expect(s.tone, BudgetTone.exceeded);
      expect(s.isExceeded, isTrue);
      expect(s.remainingMinor, -2000);
      expect(s.crossedThresholds, containsAll(<int>[50, 80, 100]));
    });

    test('should fall back to healthy/zero when amount is zero', () {
      final BudgetStatus s = BudgetStatusCalculator.calculate(
        spentMinor: 5000,
        amountMinor: 0,
      );
      expect(s.tone, BudgetTone.healthy);
      expect(s.percentSpent, 0);
      expect(s.crossedThresholds, isEmpty);
    });

    test('should honour a custom threshold list', () {
      final BudgetStatus s = BudgetStatusCalculator.calculate(
        spentMinor: 3500,
        amountMinor: 10000,
        thresholds: <int>[25, 75],
      );
      expect(s.crossedThresholds, <int>[25]);
    });

    test('should clamp negative spent to zero', () {
      final BudgetStatus s = BudgetStatusCalculator.calculate(
        spentMinor: -500,
        amountMinor: 10000,
      );
      expect(s.spentMinor, 0);
      expect(s.tone, BudgetTone.healthy);
    });
  });
}
