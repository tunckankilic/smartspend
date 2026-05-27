// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:stream_transform/stream_transform.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/delete_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_summary.dart';

part 'expense_list_event.dart';
part 'expense_list_state.dart';

const Duration _kSearchDebounce = Duration(milliseconds: 300);

/// Owns the Expenses list screen state machine.
///
/// Lifecycle:
///
/// ```text
/// ExpenseListInitial
///   → ExpenseListLoading              (subscription opened)
///   → ExpenseListLoaded { ... }       (first snapshot in)
///   → ExpenseListLoaded { ... }       (filter / search / sort changes)
///   → ExpenseListError                (stream / initial load broke)
/// ```
///
/// Filter changes are applied **immediately** by re-subscribing to the
/// repository's watch stream with the new predicate. Search input is the
/// odd one out — it's debounced 300 ms so each keystroke doesn't fire a
/// full query.
class ExpenseListBloc extends Bloc<ExpenseListEvent, ExpenseListState> {
  ExpenseListBloc({
    required ExpenseRepository repository,
    required GetExpenseSummaryUseCase getSummary,
    required DeleteExpenseUseCase deleteExpense,
  })  : _repository = repository,
        _getSummary = getSummary,
        _deleteExpense = deleteExpense,
        super(const ExpenseListInitial()) {
    on<ExpensesSubscribed>(_onSubscribed);
    on<_ExpensesSnapshotReceived>(_onSnapshot);
    on<_ExpensesSnapshotErrored>(_onSnapshotError);

    on<FilterChanged>(_onFilterChanged);
    on<CategoryFilterToggled>(_onCategoryToggled);
    on<DateRangeChanged>(_onDateRange);
    on<AmountRangeChanged>(_onAmountRange);
    on<SortChanged>(_onSortChanged);
    on<FiltersCleared>(_onFiltersCleared);

    // Search is debounced — restartable() means an in-flight handler is
    // cancelled when a newer event arrives, so we don't pay for stale
    // queries while the user is still typing.
    on<SearchQueried>(
      _onSearchQueried,
      transformer: (
        Stream<SearchQueried> events,
        Stream<SearchQueried> Function(SearchQueried) mapper,
      ) {
        return events.debounce(_kSearchDebounce).switchMap(mapper);
      },
    );

    on<ExpenseDeleted>(_onDeleted);
    on<ExpensesRefreshed>(_onRefreshed, transformer: droppable());
  }

  final ExpenseRepository _repository;
  final GetExpenseSummaryUseCase _getSummary;
  final DeleteExpenseUseCase _deleteExpense;

  StreamSubscription<List<Expense>>? _streamSub;

  @override
  Future<void> close() {
    _streamSub?.cancel();
    return super.close();
  }

  // ---------------------------------------------------------------------
  // Subscription lifecycle
  // ---------------------------------------------------------------------

  Future<void> _onSubscribed(
    ExpensesSubscribed event,
    Emitter<ExpenseListState> emit,
  ) async {
    emit(ExpenseListLoading(filter: state.filter));
    await _openSubscription(state.filter);
  }

  Future<void> _openSubscription(ExpenseFilter filter) async {
    await _streamSub?.cancel();
    _streamSub = _repository.watchExpenses(filter).listen(
      (List<Expense> rows) => add(_ExpensesSnapshotReceived(rows)),
      onError: (Object e, StackTrace _) {
        add(
          _ExpensesSnapshotErrored(
            CacheFailure(message: 'expense stream failed: $e'),
          ),
        );
      },
    );
  }

  Future<void> _onSnapshot(
    _ExpensesSnapshotReceived event,
    Emitter<ExpenseListState> emit,
  ) async {
    final Either<Failure, ExpenseSummary> summary =
        await _getSummary(GetExpenseSummaryParams(filter: state.filter));
    final ExpenseSummary safeSummary = summary.getOrElse(
      () => ExpenseSummary.empty,
    );
    emit(
      ExpenseListLoaded(
        expenses: event.expenses,
        summary: safeSummary,
        filter: state.filter,
      ),
    );
  }

  void _onSnapshotError(
    _ExpensesSnapshotErrored event,
    Emitter<ExpenseListState> emit,
  ) {
    final ExpenseListState current = state;
    if (current is ExpenseListLoaded) {
      // Keep the last good list visible; surface a transient banner.
      emit(current.copyWith(transientError: event.failure));
      return;
    }
    emit(ExpenseListError(failure: event.failure, filter: current.filter));
  }

  // ---------------------------------------------------------------------
  // Filter mutators
  // ---------------------------------------------------------------------

  Future<void> _onFilterChanged(
    FilterChanged event,
    Emitter<ExpenseListState> emit,
  ) async {
    await _applyFilter(event.filter, emit);
  }

  Future<void> _onCategoryToggled(
    CategoryFilterToggled event,
    Emitter<ExpenseListState> emit,
  ) async {
    final Set<int> next = <int>{...state.filter.categoryIds};
    if (!next.add(event.categoryId)) next.remove(event.categoryId);
    await _applyFilter(state.filter.copyWith(categoryIds: next), emit);
  }

  Future<void> _onDateRange(
    DateRangeChanged event,
    Emitter<ExpenseListState> emit,
  ) async {
    await _applyFilter(
      state.filter.copyWith(
        dateFrom: event.from,
        dateTo: event.to,
        clearDateFrom: event.from == null,
        clearDateTo: event.to == null,
      ),
      emit,
    );
  }

  Future<void> _onAmountRange(
    AmountRangeChanged event,
    Emitter<ExpenseListState> emit,
  ) async {
    await _applyFilter(
      state.filter.copyWith(
        minAmount: event.min,
        maxAmount: event.max,
        clearMinAmount: event.min == null,
        clearMaxAmount: event.max == null,
      ),
      emit,
    );
  }

  Future<void> _onSortChanged(
    SortChanged event,
    Emitter<ExpenseListState> emit,
  ) async {
    await _applyFilter(state.filter.copyWith(sortOrder: event.order), emit);
  }

  Future<void> _onFiltersCleared(
    FiltersCleared event,
    Emitter<ExpenseListState> emit,
  ) async {
    await _applyFilter(ExpenseFilter.empty, emit);
  }

  Future<void> _onSearchQueried(
    SearchQueried event,
    Emitter<ExpenseListState> emit,
  ) async {
    await _applyFilter(
      state.filter.copyWith(searchQuery: event.query.trim()),
      emit,
    );
  }

  Future<void> _applyFilter(
    ExpenseFilter next,
    Emitter<ExpenseListState> emit,
  ) async {
    final ExpenseListState current = state;
    if (current is ExpenseListLoaded) {
      // Keep showing the previous data while the new query is in flight.
      emit(current.copyWith(filter: next, clearTransientError: true));
    } else {
      emit(ExpenseListLoading(filter: next));
    }
    await _openSubscription(next);
  }

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  Future<void> _onDeleted(
    ExpenseDeleted event,
    Emitter<ExpenseListState> emit,
  ) async {
    final Either<Failure, void> result =
        await _deleteExpense(DeleteExpenseParams(id: event.id));
    result.fold(
      (Failure f) {
        final ExpenseListState current = state;
        if (current is ExpenseListLoaded) {
          emit(current.copyWith(transientError: f));
        }
      },
      (_) {
        // The watch stream will re-emit a list without the deleted row;
        // no explicit state change needed.
      },
    );
  }

  Future<void> _onRefreshed(
    ExpensesRefreshed event,
    Emitter<ExpenseListState> emit,
  ) async {
    // Sprint 3: re-open the subscription. Sprint 8 will additionally
    // trigger a pull against Supabase first.
    await _openSubscription(state.filter);
  }
}
