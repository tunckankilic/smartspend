import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Patches an existing budget. Use this for both edit-amount flows and
/// the "deactivate" toggle on the budget list.
class UpdateBudgetUseCase implements UseCase<void, UpdateBudgetParams> {
  const UpdateBudgetUseCase(this._repository);

  final BudgetRepository _repository;

  @override
  Future<Either<Failure, void>> call(UpdateBudgetParams params) {
    if (params.amountMinor != null && params.amountMinor! <= 0) {
      return Future<Either<Failure, void>>.value(
        const Left<Failure, void>(
          CacheFailure(
            message: 'budget.amount.must_be_positive',
            code: 'BUDGET_AMOUNT_INVALID',
          ),
        ),
      );
    }
    return _repository.updateBudget(
      id: params.id,
      amountMinor: params.amountMinor,
      period: params.period,
      startDate: params.startDate,
      isActive: params.isActive,
    );
  }
}

class UpdateBudgetParams extends Equatable {
  const UpdateBudgetParams({
    required this.id,
    this.amountMinor,
    this.period,
    this.startDate,
    this.isActive,
  });

  final int id;
  final int? amountMinor;
  final BudgetPeriod? period;
  final DateTime? startDate;
  final bool? isActive;

  @override
  List<Object?> get props =>
      <Object?>[id, amountMinor, period, startDate, isActive];
}
