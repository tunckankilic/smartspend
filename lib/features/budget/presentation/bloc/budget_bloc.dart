// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/usecases/compose_budget_snapshots.dart';
import 'package:smartspend/features/budget/domain/usecases/create_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/delete_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/update_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/watch_budgets.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';

part 'budget_event.dart';
part 'budget_state.dart';

/// State machine for `BudgetPage` (Sprint 6).
///
/// Subscribes to **two** Drift streams + one snapshot:
///   * `WatchBudgetsUseCase` — list of active budgets,
///   * `ExpenseRepository.watchExpenses(empty filter)` — all expenses,
///   * `ListCategoriesUseCase` — denormalized category lookup.
///
/// On either stream tick the bloc rebuilds a `List<BudgetSnapshot>`
/// by:
///   1. computing the current [BudgetWindow] for each budget at `now`,
///   2. filtering the in-memory expense list to that window (+ category
///      when the budget targets one),
///   3. summing minor units to get `spentMinor`,
///   4. calling the pure-function [BudgetStatusCalculator.calculate],
///   5. attaching the denormalized [Category] for the UI tile.
///
/// Threshold crossings (80%, 100%) trigger [NotificationService] **only
/// on transition** — the first rebuild after subscribe establishes a
/// baseline so we don't fire "you crossed 80%" on every cold start when
/// the user already crossed it days ago.
class BudgetBloc extends Bloc<BudgetEvent, BudgetState> {
  BudgetBloc({
    required WatchBudgetsUseCase watchBudgets,
    required CreateBudgetUseCase createBudget,
    required UpdateBudgetUseCase updateBudget,
    required DeleteBudgetUseCase deleteBudget,
    required ExpenseRepository expenseRepository,
    required ListCategoriesUseCase listCategories,
    required NotificationService notifications,
    DateTime Function()? now,
  })  : _watchBudgets = watchBudgets,
        _createBudget = createBudget,
        _updateBudget = updateBudget,
        _deleteBudget = deleteBudget,
        _expenseRepository = expenseRepository,
        _listCategories = listCategories,
        _notifications = notifications,
        _now = now ?? DateTime.now,
        super(const BudgetInitial()) {
    on<BudgetSubscribed>(_onSubscribed);
    on<BudgetCreated>(_onCreated, transformer: sequential());
    on<BudgetUpdated>(_onUpdated, transformer: sequential());
    on<BudgetDeleted>(_onDeleted, transformer: sequential());
    on<BudgetPermissionRequested>(
      _onPermissionRequested,
      transformer: droppable(),
    );
    on<_BudgetsTicked>(_onBudgetsTicked, transformer: restartable());
    on<_ExpensesTicked>(_onExpensesTicked, transformer: restartable());
    on<_StreamErrored>(_onStreamErrored);
  }

  final WatchBudgetsUseCase _watchBudgets;
  final CreateBudgetUseCase _createBudget;
  final UpdateBudgetUseCase _updateBudget;
  final DeleteBudgetUseCase _deleteBudget;
  final ExpenseRepository _expenseRepository;
  final ListCategoriesUseCase _listCategories;
  final NotificationService _notifications;
  final DateTime Function() _now;

  StreamSubscription<List<Budget>>? _budgetSub;
  StreamSubscription<List<Expense>>? _expenseSub;

  /// Latest values from each upstream — combineLatest by hand. The
  /// rebuild routine refuses to emit until **both** streams have ticked
  /// at least once so the first emission is a complete snapshot.
  List<Budget>? _latestBudgets;
  List<Expense>? _latestExpenses;
  List<Category> _latestCategories = const <Category>[];

  /// Per-budget memory of the highest threshold the calculator has seen
  /// crossed during this bloc's lifetime. Used to detect *fresh*
  /// crossings → notification side effects.
  final Map<int, Set<int>> _knownCrossings = <int, Set<int>>{};

  /// Toggled after the first complete rebuild. Until then notifications
  /// don't fire (avoids "you crossed 80%" on every cold start when the
  /// user has been over 80% for days already).
  bool _baselineEstablished = false;

  @override
  Future<void> close() async {
    await _budgetSub?.cancel();
    await _expenseSub?.cancel();
    return super.close();
  }

  // ---------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------

  Future<void> _onSubscribed(
    BudgetSubscribed event,
    Emitter<BudgetState> emit,
  ) async {
    emit(const BudgetLoading());

    // Categories are a one-shot read — Sprint 4's repository already
    // caches them and the list is short, so we don't bother watching it.
    final Either<Failure, List<Category>> cats =
        await _listCategories(const ListCategoriesParams());
    _latestCategories = cats.getOrElse(() => const <Category>[]);

    // Permission check is cheap and we want the banner state on the
    // very first paint.
    final bool hasPerm = await _notifications.hasPermission();

    emit(BudgetLoading(notificationsEnabled: hasPerm));

    await _budgetSub?.cancel();
    _budgetSub = _watchBudgets().listen(
      (List<Budget> rows) {
        _latestBudgets = rows;
        add(const _BudgetsTicked());
      },
      onError: (Object e, StackTrace _) {
        add(_StreamErrored(CacheFailure(message: e.toString())));
      },
    );

    await _expenseSub?.cancel();
    _expenseSub = _expenseRepository
        .watchExpenses(ExpenseFilter.empty)
        .listen(
      (List<Expense> rows) {
        _latestExpenses = rows;
        add(const _ExpensesTicked());
      },
      onError: (Object e, StackTrace _) {
        add(_StreamErrored(CacheFailure(message: e.toString())));
      },
    );
  }

  Future<void> _onCreated(
    BudgetCreated event,
    Emitter<BudgetState> emit,
  ) async {
    final Either<Failure, int> result = await _createBudget(
      CreateBudgetParams(
        amountMinor: event.amountMinor,
        period: event.period,
        startDate: event.startDate,
        categoryId: event.categoryId,
      ),
    );
    result.fold(
      (Failure f) => emit(_currentLoadedOrFailure(f)),
      // Success path needs no emission — the Drift watch will tick.
      (_) {},
    );
  }

  Future<void> _onUpdated(
    BudgetUpdated event,
    Emitter<BudgetState> emit,
  ) async {
    final Either<Failure, void> result = await _updateBudget(
      UpdateBudgetParams(
        id: event.id,
        amountMinor: event.amountMinor,
        period: event.period,
        startDate: event.startDate,
        isActive: event.isActive,
      ),
    );
    result.fold(
      (Failure f) => emit(_currentLoadedOrFailure(f)),
      (_) {},
    );
  }

  Future<void> _onDeleted(
    BudgetDeleted event,
    Emitter<BudgetState> emit,
  ) async {
    // Forget the crossings memory so a re-created budget with the same
    // id space starts fresh.
    _knownCrossings.remove(event.id);
    final Either<Failure, void> result =
        await _deleteBudget(DeleteBudgetParams(id: event.id));
    result.fold(
      (Failure f) => emit(_currentLoadedOrFailure(f)),
      (_) {},
    );
  }

  Future<void> _onPermissionRequested(
    BudgetPermissionRequested event,
    Emitter<BudgetState> emit,
  ) async {
    final bool granted = await _notifications.requestPermissions();
    final BudgetState s = state;
    if (s is BudgetLoaded) {
      emit(s.copyWith(notificationsEnabled: granted));
    } else if (s is BudgetLoading) {
      emit(BudgetLoading(notificationsEnabled: granted));
    }
  }

  Future<void> _onBudgetsTicked(
    _BudgetsTicked event,
    Emitter<BudgetState> emit,
  ) async {
    await _rebuild(emit);
  }

  Future<void> _onExpensesTicked(
    _ExpensesTicked event,
    Emitter<BudgetState> emit,
  ) async {
    await _rebuild(emit);
  }

  Future<void> _onStreamErrored(
    _StreamErrored event,
    Emitter<BudgetState> emit,
  ) async {
    emit(BudgetError(failure: event.failure));
  }

  // ---------------------------------------------------------------------
  // Snapshot composition
  // ---------------------------------------------------------------------

  Future<void> _rebuild(Emitter<BudgetState> emit) async {
    final List<Budget>? budgets = _latestBudgets;
    final List<Expense>? expenses = _latestExpenses;
    if (budgets == null || expenses == null) {
      // Still warming up — wait for the other stream's first tick.
      return;
    }
    final DateTime now = _now();
    final List<BudgetSnapshot> snapshots = BudgetSnapshotComposer.compose(
      budgets: budgets,
      expenses: expenses,
      categories: _latestCategories,
      now: now,
    );
    final Map<int, Set<int>> nextCrossings = <int, Set<int>>{
      for (final BudgetSnapshot s in snapshots)
        s.budget.id: s.status.crossedThresholds.toSet(),
    };

    final BudgetState current = state;
    final bool notificationsEnabled = switch (current) {
      BudgetLoaded(:final bool notificationsEnabled) => notificationsEnabled,
      BudgetLoading(:final bool notificationsEnabled) => notificationsEnabled,
      _ => false,
    };

    // Fire any *new* crossings — but never on the baseline rebuild.
    if (_baselineEstablished && notificationsEnabled) {
      await _fireNewCrossings(
        previous: _knownCrossings,
        next: nextCrossings,
        snapshots: snapshots,
      );
    }
    _knownCrossings
      ..clear()
      ..addAll(nextCrossings);
    _baselineEstablished = true;

    emit(
      BudgetLoaded(
        snapshots: snapshots,
        notificationsEnabled: notificationsEnabled,
      ),
    );
  }

  Future<void> _fireNewCrossings({
    required Map<int, Set<int>> previous,
    required Map<int, Set<int>> next,
    required List<BudgetSnapshot> snapshots,
  }) async {
    for (final BudgetSnapshot s in snapshots) {
      final Set<int> prev = previous[s.budget.id] ?? <int>{};
      final Set<int> now = next[s.budget.id] ?? <int>{};
      final Set<int> fresh = now.difference(prev);
      if (fresh.isEmpty) continue;
      // Pick the highest fresh threshold — if a single tick crossed 80
      // **and** 100, the user wants the more urgent alert, not two
      // notifications back-to-back.
      final int top = fresh.reduce((int a, int b) => a > b ? a : b);
      await _notifications.showBudgetWarning(
        budgetId: s.budget.id,
        percentSpent: top,
        title: _alertTitle(top),
        body: _alertBody(s, top),
      );
    }
  }

  /// Title strings are intentionally English-fallback inside the BLoC —
  /// presentation layer can override via a future `NotificationCopy`
  /// adapter once we want full l10n on notification bodies. For Sprint
  /// 6 these match the prompt's example copy.
  String _alertTitle(int percent) {
    if (percent >= 100) return 'Budget exceeded';
    return 'Budget warning';
  }

  String _alertBody(BudgetSnapshot s, int percent) {
    final String label =
        s.category?.name ?? 'General'; // matches the UI "Genel" tile.
    return '$label: %$percent';
  }

  BudgetState _currentLoadedOrFailure(Failure f) {
    final BudgetState s = state;
    if (s is BudgetLoaded) {
      return s.copyWith(transientFailure: f);
    }
    return BudgetError(failure: f);
  }
}
