import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/usecases/delete_budget.dart';
import 'package:smartspend/features/budget/presentation/bloc/budget_bloc.dart';

/// Equality contracts for [BudgetEvent] subtypes.
void main() {
  final DateTime start = DateTime.utc(2026, 7, 1);

  group('BudgetEvent equality', () {
    test('should treat value-less events as equal', () {
      expect(const BudgetSubscribed(), const BudgetSubscribed());
      expect(
        const BudgetPermissionRequested(),
        const BudgetPermissionRequested(),
      );
    });

    test('should compare BudgetCreated by all fields', () {
      expect(
        BudgetCreated(
          amountMinor: 500000,
          period: BudgetPeriod.monthly,
          startDate: start,
          categoryId: 2,
        ),
        BudgetCreated(
          amountMinor: 500000,
          period: BudgetPeriod.monthly,
          startDate: start,
          categoryId: 2,
        ),
      );
      expect(
        BudgetCreated(
          amountMinor: 500000,
          period: BudgetPeriod.monthly,
          startDate: start,
        ),
        isNot(
          BudgetCreated(
            amountMinor: 500000,
            period: BudgetPeriod.weekly,
            startDate: start,
          ),
        ),
      );
    });

    test('should compare BudgetUpdated by id and patch fields', () {
      expect(
        BudgetUpdated(id: 1, amountMinor: 250000, startDate: start),
        BudgetUpdated(id: 1, amountMinor: 250000, startDate: start),
      );
      expect(
        const BudgetUpdated(id: 1, isActive: true),
        isNot(const BudgetUpdated(id: 1, isActive: false)),
      );
    });

    test('should compare BudgetDeleted by id', () {
      expect(const BudgetDeleted(id: 4), const BudgetDeleted(id: 4));
      expect(const BudgetDeleted(id: 4), isNot(const BudgetDeleted(id: 5)));
    });

    test('should compare DeleteBudgetParams by id', () {
      expect(
        const DeleteBudgetParams(id: 4),
        const DeleteBudgetParams(id: 4),
      );
      expect(
        const DeleteBudgetParams(id: 4),
        isNot(const DeleteBudgetParams(id: 5)),
      );
    });
  });
}
