import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';

void main() {
  Budget make({int? categoryId}) => Budget(
        id: 1,
        amountMinor: 50000,
        period: BudgetPeriod.monthly,
        startDate: DateTime.utc(2026),
        isActive: true,
        categoryId: categoryId,
      );

  group('Budget.isGeneral', () {
    test('should be true when categoryId is null', () {
      expect(make().isGeneral, isTrue);
    });

    test('should be false when a category is set', () {
      expect(make(categoryId: 3).isGeneral, isFalse);
    });
  });

  group('Budget.copyWith', () {
    test('should return an identical copy when no overrides are given', () {
      final Budget b = make(categoryId: 3);
      expect(b.copyWith(), b);
    });

    test('should override the provided fields only', () {
      final Budget updated = make().copyWith(
        amountMinor: 99000,
        currency: 'EUR',
        period: BudgetPeriod.weekly,
        isActive: false,
        isPendingSync: true,
        categoryId: 7,
      );

      expect(updated.amountMinor, 99000);
      expect(updated.currency, 'EUR');
      expect(updated.period, BudgetPeriod.weekly);
      expect(updated.isActive, isFalse);
      expect(updated.isPendingSync, isTrue);
      expect(updated.categoryId, 7);
      expect(updated.id, 1);
    });

    test('clearCategory should null out an existing category', () {
      final Budget cleared = make(categoryId: 5).copyWith(clearCategory: true);
      expect(cleared.categoryId, isNull);
      expect(cleared.isGeneral, isTrue);
    });

    test('clearCategory should win over a provided categoryId', () {
      final Budget cleared =
          make(categoryId: 5).copyWith(clearCategory: true, categoryId: 9);
      expect(cleared.categoryId, isNull);
    });
  });
}
