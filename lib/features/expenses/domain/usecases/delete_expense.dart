import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Soft-delete an expense (stamps `pending_delete`).
///
/// The list query filters these rows out, so the UI sees an instant
/// removal even before the sync worker hard-deletes upstream.
class DeleteExpenseUseCase implements UseCase<void, DeleteExpenseParams> {
  const DeleteExpenseUseCase(this._repository);

  final ExpenseRepository _repository;

  @override
  Future<Either<Failure, void>> call(DeleteExpenseParams params) {
    return _repository.deleteExpense(params.id);
  }
}

class DeleteExpenseParams extends Equatable {
  const DeleteExpenseParams({required this.id});

  final int id;

  @override
  List<Object?> get props => <Object?>[id];
}
