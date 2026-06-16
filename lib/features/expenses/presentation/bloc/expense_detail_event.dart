part of 'expense_detail_bloc.dart';

sealed class ExpenseDetailEvent extends Equatable {
  const ExpenseDetailEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Load the expense with the supplied local id.
final class ExpenseDetailRequested extends ExpenseDetailEvent {
  const ExpenseDetailRequested({required this.id});

  final int id;

  @override
  List<Object?> get props => <Object?>[id];
}

/// Delete the currently-loaded expense.
final class ExpenseDetailDeletedRequested extends ExpenseDetailEvent {
  const ExpenseDetailDeletedRequested();
}
