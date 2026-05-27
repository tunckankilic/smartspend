part of 'expense_list_bloc.dart';

/// Inbound events for [ExpenseListBloc].
///
/// Past-tense naming (`ExpensesSubscribed`, `ExpenseDeleted`) per CLAUDE.md.
sealed class ExpenseListEvent extends Equatable {
  const ExpenseListEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Open the underlying watch stream. Idempotent — calling twice tears
/// down the old subscription before starting a fresh one with the
/// current filter.
final class ExpensesSubscribed extends ExpenseListEvent {
  const ExpensesSubscribed();
}

/// Snapshot emitted by the repository stream. Private to the bloc — UI
/// never dispatches this directly.
final class _ExpensesSnapshotReceived extends ExpenseListEvent {
  const _ExpensesSnapshotReceived(this.expenses);

  final List<Expense> expenses;

  @override
  List<Object?> get props => <Object?>[expenses];
}

/// Stream emitted an error.
final class _ExpensesSnapshotErrored extends ExpenseListEvent {
  const _ExpensesSnapshotErrored(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

/// Replace the whole filter snapshot.
final class FilterChanged extends ExpenseListEvent {
  const FilterChanged({required this.filter});

  final ExpenseFilter filter;

  @override
  List<Object?> get props => <Object?>[filter];
}

/// Toggle a category id in/out of the filter set.
final class CategoryFilterToggled extends ExpenseListEvent {
  const CategoryFilterToggled({required this.categoryId});

  final int categoryId;

  @override
  List<Object?> get props => <Object?>[categoryId];
}

/// Replace the date range (either bound may be `null`).
final class DateRangeChanged extends ExpenseListEvent {
  const DateRangeChanged({this.from, this.to});

  final DateTime? from;
  final DateTime? to;

  @override
  List<Object?> get props => <Object?>[from, to];
}

/// Replace min/max amount (minor units).
final class AmountRangeChanged extends ExpenseListEvent {
  const AmountRangeChanged({this.min, this.max});

  final int? min;
  final int? max;

  @override
  List<Object?> get props => <Object?>[min, max];
}

/// Update the sort order.
final class SortChanged extends ExpenseListEvent {
  const SortChanged({required this.order});

  final ExpenseSortOrder order;

  @override
  List<Object?> get props => <Object?>[order];
}

/// Update the search query. Debounced via the bloc's event transformer.
final class SearchQueried extends ExpenseListEvent {
  const SearchQueried({required this.query});

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}

/// Wipe all filters back to [ExpenseFilter.empty].
final class FiltersCleared extends ExpenseListEvent {
  const FiltersCleared();
}

/// Swipe-to-delete dispatches this with the expense's local id.
final class ExpenseDeleted extends ExpenseListEvent {
  const ExpenseDeleted({required this.id});

  final int id;

  @override
  List<Object?> get props => <Object?>[id];
}

/// Pull-to-refresh — Sprint 3 just re-fetches Drift; Sprint 8 will
/// trigger the sync worker before rebuilding.
final class ExpensesRefreshed extends ExpenseListEvent {
  const ExpensesRefreshed();
}
