import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/category_spike_insight.dart';
import 'package:smartspend/features/dashboard/domain/usecases/insights/insight_pipeline.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Sprint 5's spike threshold (kept as a top-level constant to avoid
/// breaking imports from old code paths and tests).
const double kInsightSpikeThresholdPercent =
    CategorySpikeInsightEvaluator.thresholdPercent;
const int kInsightMinCurrentMinor =
    CategorySpikeInsightEvaluator.minCurrentMinor;

/// Public surface for the bloc. Sprint 6 swapped the body for the
/// 5-rule [DashboardInsightPipeline] but the call site is unchanged.
///
/// `evaluate` is exposed for unit tests so they can call the engine
/// without `async`/`Either` ceremony.
class GetDashboardInsightUseCase
    implements UseCase<DashboardInsight?, GetDashboardInsightParams> {
  const GetDashboardInsightUseCase();

  @override
  Future<Either<Failure, DashboardInsight?>> call(
    GetDashboardInsightParams params,
  ) async {
    return right(
      evaluate(
        params.snapshot,
        budgets: params.budgets,
        now: params.now,
      ),
    );
  }

  /// Direct (sync) evaluator. Defaults preserve Sprint 5 callers — pass
  /// no budgets and the pipeline falls through to the category-spike
  /// rule, which is what the Sprint 5 tests assert against.
  static DashboardInsight? evaluate(
    DashboardSnapshot snapshot, {
    List<BudgetSnapshot> budgets = const <BudgetSnapshot>[],
    DateTime? now,
  }) {
    return DashboardInsightPipeline.resolve(
      snapshot: snapshot,
      budgets: budgets,
      now: now ?? DateTime.now(),
    );
  }
}

class GetDashboardInsightParams extends Equatable {
  const GetDashboardInsightParams({
    required this.snapshot,
    this.budgets = const <BudgetSnapshot>[],
    this.now,
  });

  final DashboardSnapshot snapshot;
  final List<BudgetSnapshot> budgets;

  /// Pass-through clock — the bloc supplies a real one, tests pass a
  /// fixed instant. `null` collapses to `DateTime.now()` at the call
  /// site (see [GetDashboardInsightUseCase.call]).
  final DateTime? now;

  @override
  List<Object?> get props => <Object?>[snapshot, budgets, now];
}
