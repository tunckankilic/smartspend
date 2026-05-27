// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_snapshot.dart';
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
    required GetDashboardSnapshotUseCase getSnapshot,
    required ListCategoriesUseCase listCategories,
    DateTime Function()? now,
  })  : _repository = repository,
        _getSnapshot = getSnapshot,
        _listCategories = listCategories,
        _now = now ?? DateTime.now,
        super(const DashboardInitial()) {
    on<DashboardSubscribed>(_onSubscribed);
    on<DashboardPeriodChanged>(_onPeriodChanged, transformer: sequential());
    on<DashboardRefreshed>(_onRefreshed, transformer: droppable());
    on<_DashboardWatchTicked>(_onWatchTicked, transformer: restartable());
    on<_DashboardWatchErrored>(_onWatchErrored);
  }

  final ExpenseRepository _repository;
  final GetDashboardSnapshotUseCase _getSnapshot;
  final ListCategoriesUseCase _listCategories;
  final DateTime Function() _now;

  StreamSubscription<List<Expense>>? _streamSub;

  @override
  Future<void> close() {
    _streamSub?.cancel();
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

    final DashboardInsight? insight =
        GetDashboardInsightUseCase.evaluate(snapshot);

    final List<Category> categories = await _loadCategories();

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
    // Push an eager first tick: real Drift streams emit on subscribe,
    // but we don't want to rely on that — keeping the rebuild explicit
    // also makes test mocks (`StreamController`) easier to write.
    add(const _DashboardWatchTicked());
  }

  Future<List<Category>> _loadCategories() async {
    final Either<Failure, List<Category>> result =
        await _listCategories(const ListCategoriesParams());
    return result.getOrElse(() => const <Category>[]);
  }
}
