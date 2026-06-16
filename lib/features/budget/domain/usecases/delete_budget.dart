import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Soft-deletes a budget — repository writes `sync_status = 'pending_delete'`
/// and queries automatically exclude these rows.
class DeleteBudgetUseCase implements UseCase<void, DeleteBudgetParams> {
  const DeleteBudgetUseCase(this._repository);

  final BudgetRepository _repository;

  @override
  Future<Either<Failure, void>> call(DeleteBudgetParams params) {
    return _repository.deleteBudget(params.id);
  }
}

class DeleteBudgetParams extends Equatable {
  const DeleteBudgetParams({required this.id});

  final int id;

  @override
  List<Object?> get props => <Object?>[id];
}
