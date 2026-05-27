part of 'expense_list_bloc.dart';

/// Observable outputs of [ExpenseListBloc].
sealed class ExpenseListState extends Equatable {
  const ExpenseListState({required this.filter});

  /// Current filter snapshot — kept on every state so the UI can render
  /// chips without juggling a separate cubit.
  final ExpenseFilter filter;

  @override
  List<Object?> get props => <Object?>[filter];
}

/// Pre-subscription. The page bloc starts here before the watch stream
/// ever fires.
final class ExpenseListInitial extends ExpenseListState {
  const ExpenseListInitial({super.filter = ExpenseFilter.empty});
}

/// First snapshot pending — shows the page-level spinner. Subsequent
/// reloads stay in [ExpenseListLoaded] with a banner; we don't blank
/// out the list on every filter change.
final class ExpenseListLoading extends ExpenseListState {
  const ExpenseListLoading({super.filter = ExpenseFilter.empty});
}

/// Steady state — list + summary computed from the latest stream
/// emission.
final class ExpenseListLoaded extends ExpenseListState {
  const ExpenseListLoaded({
    required this.expenses,
    required this.summary,
    required super.filter,
    this.transientError,
  });

  /// Filtered + sorted list ready for the page.
  final List<Expense> expenses;

  /// Aggregated totals for the app bar / sticky header.
  final ExpenseSummary summary;

  /// Set when a write op (delete, etc.) failed; cleared on the next
  /// stream emission.
  final Failure? transientError;

  ExpenseListLoaded copyWith({
    List<Expense>? expenses,
    ExpenseSummary? summary,
    ExpenseFilter? filter,
    Failure? transientError,
    bool clearTransientError = false,
  }) {
    return ExpenseListLoaded(
      expenses: expenses ?? this.expenses,
      summary: summary ?? this.summary,
      filter: filter ?? this.filter,
      transientError: clearTransientError
          ? null
          : (transientError ?? this.transientError),
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[...super.props, expenses, summary, transientError];
}

/// Hard failure — the stream / initial load couldn't produce any data.
final class ExpenseListError extends ExpenseListState {
  const ExpenseListError({required this.failure, required super.filter});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[...super.props, failure];
}
