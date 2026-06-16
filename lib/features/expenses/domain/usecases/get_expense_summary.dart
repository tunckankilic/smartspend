import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Aggregated totals for the matched filter window — feeds the app bar
/// counter on the list page and (Sprint 5) the dashboard.
class GetExpenseSummaryUseCase
    implements UseCase<ExpenseSummary, GetExpenseSummaryParams> {
  const GetExpenseSummaryUseCase(this._repository);

  final ExpenseRepository _repository;

  @override
  Future<Either<Failure, ExpenseSummary>> call(
    GetExpenseSummaryParams params,
  ) {
    return _repository.getSummary(params.filter);
  }
}

class GetExpenseSummaryParams extends Equatable {
  const GetExpenseSummaryParams({this.filter = ExpenseFilter.empty});

  final ExpenseFilter filter;

  @override
  List<Object?> get props => <Object?>[filter];
}
