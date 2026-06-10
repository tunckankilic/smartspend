import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/delete_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_by_id.dart';

part 'expense_detail_event.dart';
part 'expense_detail_state.dart';

/// Owns the Expense detail screen state.
///
/// Lifecycle:
///
/// ```text
/// ExpenseDetailInitial
///   → ExpenseDetailLoading  (id received, fetch in flight)
///   → ExpenseDetailLoaded   (row materialized, or `null` if missing)
///   → ExpenseDetailDeleted  (terminal — caller should pop)
///   → ExpenseDetailError    (recoverable; ready state preserved)
/// ```
class ExpenseDetailBloc extends Bloc<ExpenseDetailEvent, ExpenseDetailState> {
  ExpenseDetailBloc({
    required GetExpenseByIdUseCase getExpenseById,
    required DeleteExpenseUseCase deleteExpense,
  }) : _getById = getExpenseById,
       _delete = deleteExpense,
       super(const ExpenseDetailInitial()) {
    on<ExpenseDetailRequested>(_onRequested);
    on<ExpenseDetailDeletedRequested>(_onDelete);
  }

  final GetExpenseByIdUseCase _getById;
  final DeleteExpenseUseCase _delete;

  Future<void> _onRequested(
    ExpenseDetailRequested event,
    Emitter<ExpenseDetailState> emit,
  ) async {
    emit(const ExpenseDetailLoading());
    final Either<Failure, Expense?> result = await _getById(
      GetExpenseByIdParams(id: event.id),
    );
    result.fold(
      (Failure f) => emit(ExpenseDetailError(failure: f)),
      (Expense? expense) => emit(ExpenseDetailLoaded(expense: expense)),
    );
  }

  Future<void> _onDelete(
    ExpenseDetailDeletedRequested event,
    Emitter<ExpenseDetailState> emit,
  ) async {
    final ExpenseDetailState current = state;
    if (current is! ExpenseDetailLoaded || current.expense == null) return;
    final Either<Failure, void> result = await _delete(
      DeleteExpenseParams(id: current.expense!.id),
    );
    result.fold(
      (Failure f) => emit(ExpenseDetailError(failure: f)),
      (_) => emit(const ExpenseDetailDeleted()),
    );
  }
}
