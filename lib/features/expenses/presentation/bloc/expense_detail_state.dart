part of 'expense_detail_bloc.dart';

sealed class ExpenseDetailState extends Equatable {
  const ExpenseDetailState();

  @override
  List<Object?> get props => const <Object?>[];
}

final class ExpenseDetailInitial extends ExpenseDetailState {
  const ExpenseDetailInitial();
}

final class ExpenseDetailLoading extends ExpenseDetailState {
  const ExpenseDetailLoading();
}

/// Steady state. [expense] is `null` when the id didn't resolve — the
/// page renders a 404 in that case.
final class ExpenseDetailLoaded extends ExpenseDetailState {
  const ExpenseDetailLoaded({required this.expense});

  final Expense? expense;

  @override
  List<Object?> get props => <Object?>[expense];
}

/// Terminal — caller should pop. The list page will re-emit a snapshot
/// without the deleted row.
final class ExpenseDetailDeleted extends ExpenseDetailState {
  const ExpenseDetailDeleted();
}

/// Recoverable failure (delete / fetch). UI shows a snackbar and stays
/// on the page.
final class ExpenseDetailError extends ExpenseDetailState {
  const ExpenseDetailError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
