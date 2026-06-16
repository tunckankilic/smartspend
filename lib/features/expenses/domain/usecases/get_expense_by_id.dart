import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Fetches a single expense by its local Drift PK. Returns `Right(null)`
/// for ids that don't resolve so the detail page can render a 404 state.
class GetExpenseByIdUseCase
    implements UseCase<Expense?, GetExpenseByIdParams> {
  const GetExpenseByIdUseCase(this._repository);

  final ExpenseRepository _repository;

  @override
  Future<Either<Failure, Expense?>> call(GetExpenseByIdParams params) {
    return _repository.getExpenseById(params.id);
  }
}

class GetExpenseByIdParams extends Equatable {
  const GetExpenseByIdParams({required this.id});

  final int id;

  @override
  List<Object?> get props => <Object?>[id];
}
