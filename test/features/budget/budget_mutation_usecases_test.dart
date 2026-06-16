import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';
import 'package:smartspend/features/budget/domain/usecases/create_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/delete_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/update_budget.dart';

class _MockBudgetRepository extends Mock implements BudgetRepository {}

void main() {
  late _MockBudgetRepository repo;
  final DateTime start = DateTime.utc(2026);

  setUpAll(() {
    registerFallbackValue(BudgetPeriod.monthly);
    registerFallbackValue(DateTime.utc(2026));
  });

  setUp(() {
    repo = _MockBudgetRepository();
  });

  group('CreateBudgetUseCase', () {
    test('should reject a non-positive amount without touching the repo',
        () async {
      final Either<Failure, int> result = await CreateBudgetUseCase(repo)(
        CreateBudgetParams(
          amountMinor: 0,
          period: BudgetPeriod.monthly,
          startDate: start,
        ),
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f.code, 'BUDGET_AMOUNT_INVALID'),
        (_) => fail('expected Left'),
      );
      verifyNever(
        () => repo.createBudget(
          amountMinor: any(named: 'amountMinor'),
          period: any(named: 'period'),
          startDate: any(named: 'startDate'),
          categoryId: any(named: 'categoryId'),
        ),
      );
    });

    test('should forward a valid budget to the repository', () async {
      when(
        () => repo.createBudget(
          amountMinor: 50000,
          period: BudgetPeriod.monthly,
          startDate: start,
          categoryId: 3,
        ),
      ).thenAnswer((_) async => const Right<Failure, int>(11));

      final Either<Failure, int> result = await CreateBudgetUseCase(repo)(
        CreateBudgetParams(
          amountMinor: 50000,
          period: BudgetPeriod.monthly,
          startDate: start,
          categoryId: 3,
        ),
      );

      expect(result, const Right<Failure, int>(11));
    });
  });

  group('UpdateBudgetUseCase', () {
    test('should reject a non-positive amount', () async {
      final Either<Failure, void> result = await UpdateBudgetUseCase(repo)(
        const UpdateBudgetParams(id: 1, amountMinor: -5),
      );

      expect(result.isLeft(), isTrue);
    });

    test('should forward a valid patch to the repository', () async {
      when(
        () => repo.updateBudget(
          id: 1,
          amountMinor: 7000,
          period: null,
          startDate: null,
          isActive: false,
        ),
      ).thenAnswer((_) async => const Right<Failure, void>(null));

      final Either<Failure, void> result = await UpdateBudgetUseCase(repo)(
        const UpdateBudgetParams(id: 1, amountMinor: 7000, isActive: false),
      );

      expect(result.isRight(), isTrue);
    });
  });

  group('DeleteBudgetUseCase', () {
    test('should forward the id to the repository', () async {
      when(() => repo.deleteBudget(4))
          .thenAnswer((_) async => const Right<Failure, void>(null));

      final Either<Failure, void> result =
          await DeleteBudgetUseCase(repo)(const DeleteBudgetParams(id: 4));

      expect(result.isRight(), isTrue);
      verify(() => repo.deleteBudget(4)).called(1);
    });
  });
}
