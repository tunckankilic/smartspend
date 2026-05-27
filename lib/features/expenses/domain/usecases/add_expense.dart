import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Inserts a manual expense — driven by Sprint 3.2's AddExpense form.
///
/// Returns the inserted row's local Drift PK on success.
class AddExpenseUseCase implements UseCase<int, AddExpenseParams> {
  const AddExpenseUseCase(this._repository);

  final ExpenseRepository _repository;

  @override
  Future<Either<Failure, int>> call(AddExpenseParams params) {
    return _repository.addExpense(
      amount: params.amount,
      categoryId: params.categoryId,
      date: params.date,
      isManual: params.isManual,
      note: params.note,
      receiptId: params.receiptId,
      isRecurring: params.isRecurring,
      recurringPeriod: params.recurringPeriod?.name,
      tags: params.tags,
    );
  }
}

class AddExpenseParams extends Equatable {
  const AddExpenseParams({
    required this.amount,
    required this.categoryId,
    required this.date,
    this.isManual = true,
    this.note,
    this.receiptId,
    this.isRecurring = false,
    this.recurringPeriod,
    this.tags = const <String>[],
  });

  final int amount;
  final int categoryId;
  final DateTime date;
  final bool isManual;
  final String? note;
  final int? receiptId;
  final bool isRecurring;
  final RecurringPeriod? recurringPeriod;
  final List<String> tags;

  @override
  List<Object?> get props => <Object?>[
        amount,
        categoryId,
        date,
        isManual,
        note,
        receiptId,
        isRecurring,
        recurringPeriod,
        tags,
      ];
}
