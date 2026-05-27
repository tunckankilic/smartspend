import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Patch an existing expense — stamps the row `pending_update`.
class UpdateExpenseUseCase implements UseCase<void, UpdateExpenseParams> {
  const UpdateExpenseUseCase(this._repository);

  final ExpenseRepository _repository;

  @override
  Future<Either<Failure, void>> call(UpdateExpenseParams params) {
    return _repository.updateExpense(
      id: params.id,
      amount: params.amount,
      categoryId: params.categoryId,
      date: params.date,
      note: params.note,
      clearNote: params.clearNote,
      isRecurring: params.isRecurring,
      recurringPeriod: params.recurringPeriod?.name,
      clearRecurringPeriod: params.clearRecurringPeriod,
      tags: params.tags,
    );
  }
}

class UpdateExpenseParams extends Equatable {
  const UpdateExpenseParams({
    required this.id,
    this.amount,
    this.categoryId,
    this.date,
    this.note,
    this.clearNote = false,
    this.isRecurring,
    this.recurringPeriod,
    this.clearRecurringPeriod = false,
    this.tags,
  });

  final int id;
  final int? amount;
  final int? categoryId;
  final DateTime? date;
  final String? note;
  final bool clearNote;
  final bool? isRecurring;
  final RecurringPeriod? recurringPeriod;
  final bool clearRecurringPeriod;

  /// `null` leaves tags untouched. An empty list clears them.
  final List<String>? tags;

  @override
  List<Object?> get props => <Object?>[
        id,
        amount,
        categoryId,
        date,
        note,
        clearNote,
        isRecurring,
        recurringPeriod,
        clearRecurringPeriod,
        tags,
      ];
}
