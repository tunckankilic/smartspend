import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/delete_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_by_id.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_summary.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expenses.dart';

class _MockExpenseRepository extends Mock implements ExpenseRepository {}

void main() {
  late _MockExpenseRepository repo;

  setUpAll(() {
    registerFallbackValue(ExpenseFilter.empty);
  });

  setUp(() {
    repo = _MockExpenseRepository();
  });

  group('GetExpensesUseCase', () {
    test('should forward the filter and return the list', () async {
      when(() => repo.getExpenses(any())).thenAnswer(
        (_) async => const Right<Failure, List<Expense>>(<Expense>[]),
      );

      final Either<Failure, List<Expense>> result =
          await GetExpensesUseCase(repo)(const GetExpensesParams());

      expect(result.isRight(), isTrue);
      verify(() => repo.getExpenses(ExpenseFilter.empty)).called(1);
    });
  });

  group('GetExpenseByIdUseCase', () {
    test('should return Right(null) for an unknown id', () async {
      when(() => repo.getExpenseById(99))
          .thenAnswer((_) async => const Right<Failure, Expense?>(null));

      final Either<Failure, Expense?> result =
          await GetExpenseByIdUseCase(repo)(
        const GetExpenseByIdParams(id: 99),
      );

      expect(result, const Right<Failure, Expense?>(null));
      verify(() => repo.getExpenseById(99)).called(1);
    });
  });

  group('GetExpenseSummaryUseCase', () {
    test('should delegate to getSummary', () async {
      when(() => repo.getSummary(any())).thenAnswer(
        (_) async =>
            const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
      );

      final Either<Failure, ExpenseSummary> result =
          await GetExpenseSummaryUseCase(repo)(
        const GetExpenseSummaryParams(),
      );

      expect(
        result,
        const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
      );
      verify(() => repo.getSummary(ExpenseFilter.empty)).called(1);
    });
  });

  group('DeleteExpenseUseCase', () {
    test('should forward the id to the repository', () async {
      when(() => repo.deleteExpense(7))
          .thenAnswer((_) async => const Right<Failure, void>(null));

      final Either<Failure, void> result =
          await DeleteExpenseUseCase(repo)(const DeleteExpenseParams(id: 7));

      expect(result.isRight(), isTrue);
      verify(() => repo.deleteExpense(7)).called(1);
    });
  });
}
