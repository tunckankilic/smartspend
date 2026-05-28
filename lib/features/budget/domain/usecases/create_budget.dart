import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Inserts a new budget. Returns the local Drift PK on success.
///
/// Validates that:
///   * `amountMinor > 0` — the UI also blocks this, defence in depth.
///
/// "Only one active general budget" / "only one active per category"
/// is enforced by the BLoC because it owns the active-list snapshot
/// and can produce a more actionable error message than a use case
/// that would need to re-query the repository on every call.
class CreateBudgetUseCase implements UseCase<int, CreateBudgetParams> {
  const CreateBudgetUseCase(this._repository);

  final BudgetRepository _repository;

  @override
  Future<Either<Failure, int>> call(CreateBudgetParams params) {
    if (params.amountMinor <= 0) {
      return Future<Either<Failure, int>>.value(
        const Left<Failure, int>(
          CacheFailure(
            message: 'budget.amount.must_be_positive',
            code: 'BUDGET_AMOUNT_INVALID',
          ),
        ),
      );
    }
    return _repository.createBudget(
      amountMinor: params.amountMinor,
      period: params.period,
      startDate: params.startDate,
      categoryId: params.categoryId,
    );
  }
}

class CreateBudgetParams extends Equatable {
  const CreateBudgetParams({
    required this.amountMinor,
    required this.period,
    required this.startDate,
    this.categoryId,
  });

  final int amountMinor;
  final BudgetPeriod period;
  final DateTime startDate;

  /// `null` = general / total budget.
  final int? categoryId;

  @override
  List<Object?> get props =>
      <Object?>[amountMinor, period, startDate, categoryId];
}
