import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/delete_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_by_id.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_summary.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expenses.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

class _MockRepository extends Mock implements ExpenseRepository {}

/// Params equality contracts for the small expense query usecases + the
/// [GetExpensesUseCase] pass-through.
void main() {
  group('GetExpensesUseCase', () {
    test('should forward the filter to the repository', () async {
      final _MockRepository repository = _MockRepository();
      when(() => repository.getExpenses(ExpenseFilter.empty)).thenAnswer(
        (_) async => const Right<Failure, List<Expense>>(<Expense>[]),
      );

      final Either<Failure, List<Expense>> result = await GetExpensesUseCase(
        repository,
      )(const GetExpensesParams());

      expect(result.isRight(), isTrue);
      verify(() => repository.getExpenses(ExpenseFilter.empty)).called(1);
    });
  });

  group('params equality', () {
    test('should compare GetExpensesParams by filter', () {
      expect(const GetExpensesParams(), const GetExpensesParams());
    });

    test('should compare GetExpenseByIdParams by id', () {
      expect(
        const GetExpenseByIdParams(id: 1),
        const GetExpenseByIdParams(id: 1),
      );
      expect(
        const GetExpenseByIdParams(id: 1),
        isNot(const GetExpenseByIdParams(id: 2)),
      );
    });

    test('should compare GetExpenseSummaryParams by filter', () {
      expect(
        const GetExpenseSummaryParams(),
        const GetExpenseSummaryParams(),
      );
    });

    test('should compare DeleteExpenseParams by id', () {
      expect(
        const DeleteExpenseParams(id: 1),
        const DeleteExpenseParams(id: 1),
      );
      expect(
        const DeleteExpenseParams(id: 1),
        isNot(const DeleteExpenseParams(id: 2)),
      );
    });

    test('should treat NoParams instances as equal', () {
      expect(const NoParams(), const NoParams());
    });
  });
}
