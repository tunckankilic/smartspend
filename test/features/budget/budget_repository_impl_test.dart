import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/data/repositories/budget_repository_impl.dart';
import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late BudgetRepositoryImpl repo;

  setUp(() {
    db = createTestDatabase();
    repo = BudgetRepositoryImpl(budgetDao: db.budgetDao);
  });
  tearDown(() async => db.close());

  group('createBudget + getActiveBudgets', () {
    test('should create a budget and read it back as active', () async {
      final Either<Failure, int> created = await repo.createBudget(
        amountMinor: 150000,
        period: BudgetPeriod.monthly,
        startDate: DateTime.utc(2026, 5, 1),
      );
      expect(created.isRight(), isTrue);

      final Either<Failure, List<Budget>> active =
          await repo.getActiveBudgets();
      final List<Budget> budgets = active.getOrElse(() => <Budget>[]);
      expect(budgets, hasLength(1));
      expect(budgets.first.amountMinor, 150000);
      expect(budgets.first.period, BudgetPeriod.monthly);
      expect(budgets.first.isPendingSync, isTrue);
    });
  });

  group('watchActiveBudgets', () {
    test('should emit active budgets', () async {
      await repo.createBudget(
        amountMinor: 50000,
        period: BudgetPeriod.weekly,
        startDate: DateTime.utc(2026, 5, 1),
      );
      final List<Budget> emitted = await repo.watchActiveBudgets().first;
      expect(emitted, hasLength(1));
      expect(emitted.first.period, BudgetPeriod.weekly);
    });
  });

  group('updateBudget', () {
    test('should update amount and period', () async {
      final int id = (await repo.createBudget(
        amountMinor: 10000,
        period: BudgetPeriod.weekly,
        startDate: DateTime.utc(2026, 5, 1),
      ))
          .getOrElse(() => -1);

      final Either<Failure, void> result = await repo.updateBudget(
        id: id,
        amountMinor: 99999,
        period: BudgetPeriod.monthly,
      );
      expect(result.isRight(), isTrue);

      final Budget updated = (await repo.getActiveBudgets())
          .getOrElse(() => <Budget>[])
          .firstWhere((Budget b) => b.id == id);
      expect(updated.amountMinor, 99999);
      expect(updated.period, BudgetPeriod.monthly);
    });
  });

  group('deleteBudget', () {
    test('should soft-delete so it leaves the active list', () async {
      final int id = (await repo.createBudget(
        amountMinor: 10000,
        period: BudgetPeriod.monthly,
        startDate: DateTime.utc(2026, 5, 1),
      ))
          .getOrElse(() => -1);

      final Either<Failure, void> result = await repo.deleteBudget(id);
      expect(result.isRight(), isTrue);

      final List<Budget> active =
          (await repo.getActiveBudgets()).getOrElse(() => <Budget>[]);
      expect(active, isEmpty);
    });
  });
}
