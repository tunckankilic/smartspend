import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Loads a filtered + sorted snapshot of expenses for the list page.
class GetExpensesUseCase implements UseCase<List<Expense>, GetExpensesParams> {
  const GetExpensesUseCase(this._repository);

  final ExpenseRepository _repository;

  @override
  Future<Either<Failure, List<Expense>>> call(GetExpensesParams params) {
    return _repository.getExpenses(params.filter);
  }
}

class GetExpensesParams extends Equatable {
  const GetExpensesParams({this.filter = ExpenseFilter.empty});

  final ExpenseFilter filter;

  @override
  List<Object?> get props => <Object?>[filter];
}
