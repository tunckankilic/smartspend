// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';
import 'package:smartspend/features/budget/domain/usecases/compose_budget_snapshots.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/insight_pipeline.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

/// Owns the dashboard state machine.
///
/// On [DashboardSubscribed] the bloc:
///   1. resolves the current [DashboardPeriod] to a Drift watch stream;
///   2. on every stream emission, rebuilds the [DashboardSnapshot] via
///      [GetDashboardSnapshotUseCase] and recomputes the
///      [DashboardInsight] off of it.
///
/// Period changes simply tear down the existing watch and re-subscribe.
/// Sprint 8 will wrap this in a Supabase Realtime push so cross-device
/// edits also fan-in here; today the watch stream alone is enough since
/// every write goes through Drift first.
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc({
    required ExpenseRepository repository,
    required BudgetRepository budgetRepository,
    required GetDashboardSnapshotUseCase getSnapshot,
    required ListCategoriesUseCase listCategories,
    DateTime Function()? now,
  })  : _repository = repository,
        _budgetRepository = budgetRepository,
        _getSnapshot = getSnapshot,
        _listCategories = listCategories,
        _now = now ?? DateTime.now,
        super(const DashboardInitial()) {
    on<DashboardSubscribed>(_onSubscribed);
    on<DashboardPeriodChanged>(_onPeriodChanged, transformer: sequential());
    on<DashboardRefreshed>(_onRefreshed, transformer: droppable());
    on<_DashboardWatchTicked>(_onWatchTicked, transformer: restartable());
    on<_DashboardBudgetsTicked>(
      _onBudgetsTicked,
      transformer: restartable(),
    );
    on<_DashboardWatchErrored>(_onWatchErrored);
  }

  final ExpenseRepository _repository;
  final BudgetRepository _budgetRepository;
  final GetDashboardSnapshotUseCase _getSnapshot;
  final ListCategoriesUseCase _listCategories;
  final DateTime Function() _now;

  StreamSubscription<List<Expense>>? _streamSub;
  StreamSubscription<List<Budget>>? _budgetSub;

  /// Latest active-budget snapshot — driven by the budget watch stream
  /// so the insight pipeline can fire warning / achievement rules even
  /// when no new expense has landed.
  List<Budget> _latestBudgets = const <Budget>[];

  /// Latest expense window — cached so a budget-only tick can rerun the
  /// pipeline without re-fetching from Drift.
  List<Expense> _latestExpenses = const <Expense>[];

  @override
  Future<void> close() {
    _streamSub?.cancel();
    _budgetSub?.cancel();
    return super.close();
  }

  // ---------------------------------------------------------------------
  // Public handlers
  // ---------------------------------------------------------------------

  Future<void> _onSubscribed(
    DashboardSubscribed event,
    Emitter<DashboardState> emit,
  ) async {
    emit(DashboardLoading(period: state.period));
    await _resubscribe(state.period);
  }

  Future<void> _onPeriodChanged(
    DashboardPeriodChanged event,
    Emitter<DashboardState> emit,
  ) async {
    emit(DashboardLoading(period: event.period));
    await _resubscribe(event.period);
  }

  Future<void> _onRefreshed(
    DashboardRefreshed event,
    Emitter<DashboardState> emit,
  ) async {
    await _resubscribe(state.period);
  }

  Future<void> _onWatchTicked(
    _DashboardWatchTicked event,
    Emitter<DashboardState> emit,
  ) async {
    final DashboardPeriod period = state.period;

    final Either<Failure, DashboardSnapshot> snapshotEither =
        await _getSnapshot(GetDashboardSnapshotParams(period: period));
    if (snapshotEither.isLeft()) {
      emit(
        DashboardError(
          period: period,
          failure: snapshotEither.swap().getOrElse(
                () => const CacheFailure(message: 'dashboard.snapshotFailed'),
              ),
        ),
      );
      return;
    }
    final DashboardSnapshot snapshot =
        snapshotEither.getOrElse(() => DashboardSnapshot.empty);

    // Cache for the next budget-only tick.
    _latestExpenses = await _loadWindowedExpenses(period);

    final List<Category> categories = await _loadCategories();
    final List<BudgetSnapshot> budgetSnapshots =
        BudgetSnapshotComposer.compose(
      budgets: _latestBudgets,
      expenses: _latestExpenses,
      categories: categories,
      now: _now(),
    );

    final DashboardInsight? insight = DashboardInsightPipeline.resolve(
      snapshot: snapshot,
      budgets: budgetSnapshots,
      now: _now(),
    );

    emit(
      DashboardLoaded(
        period: period,
        snapshot: snapshot,
        insight: insight,
        categories: categories,
      ),
    );
  }

  Future<void> _onWatchErrored(
    _DashboardWatchErrored event,
    Emitter<DashboardState> emit,
  ) async {
    emit(
      DashboardError(
        period: state.period,
        failure: event.failure,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  Future<void> _resubscribe(DashboardPeriod period) async {
    await _streamSub?.cancel();
    final Stream<List<Expense>> stream = _repository.watchExpenses(
      period.resolve(_now()).toFilter(),
    );
    _streamSub = stream.listen(
      (List<Expense> _) => add(const _DashboardWatchTicked()),
      onError: (Object e, StackTrace _) {
        add(
          _DashboardWatchErrored(CacheFailure(message: e.toString())),
        );
      },
    );

    // Budget watch is independent of the period filter — active budgets
    // are always relevant for the insight pipeline.
    await _budgetSub?.cancel();
    _budgetSub = _budgetRepository.watchActiveBudgets().listen(
      (List<Budget> rows) {
        _latestBudgets = rows;
        add(const _DashboardBudgetsTicked());
      },
      onError: (Object e, StackTrace _) {
        // Budget stream failure shouldn't tear down the whole dashboard
        // — surface it via Sentry breadcrumb (BlocObserver) and keep
        // the last-known snapshot.
        _latestBudgets = const <Budget>[];
      },
    );

    // Push an eager first tick: real Drift streams emit on subscribe,
    // but we don't want to rely on that — keeping the rebuild explicit
    // also makes test mocks (`StreamController`) easier to write.
    add(const _DashboardWatchTicked());
  }

  Future<void> _onBudgetsTicked(
    _DashboardBudgetsTicked event,
    Emitter<DashboardState> emit,
  ) async {
    final DashboardState s = state;
    if (s is! DashboardLoaded) {
      // First snapshot still pending — the next expense tick will
      // include budgets naturally.
      return;
    }
    final List<BudgetSnapshot> budgetSnapshots =
        BudgetSnapshotComposer.compose(
      budgets: _latestBudgets,
      expenses: _latestExpenses,
      categories: s.categories,
      now: _now(),
    );
    final DashboardInsight? insight = DashboardInsightPipeline.resolve(
      snapshot: s.snapshot,
      budgets: budgetSnapshots,
      now: _now(),
    );
    emit(
      DashboardLoaded(
        period: s.period,
        snapshot: s.snapshot,
        insight: insight,
        categories: s.categories,
      ),
    );
  }

  Future<List<Category>> _loadCategories() async {
    final Either<Failure, List<Category>> result =
        await _listCategories(const ListCategoriesParams());
    return result.getOrElse(() => const <Category>[]);
  }

  Future<List<Expense>> _loadWindowedExpenses(DashboardPeriod period) async {
    final Either<Failure, List<Expense>> result =
        await _repository.getExpenses(period.resolve(_now()).toFilter());
    return result.getOrElse(() => const <Expense>[]);
  }
}
