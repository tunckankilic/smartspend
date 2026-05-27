import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Sprint 5 hard-codes the spike threshold at 20% per the prompt — Sprint
/// 6's budget feature will own configurable thresholds.
const double kInsightSpikeThresholdPercent = 20;

/// Minimum minor-unit spend in the *current* period before a category is
/// eligible. Without this, a category that jumped from ₺1 → ₺5 (a 400%
/// "spike") would dominate the banner.
const int kInsightMinCurrentMinor = 10000; // ₺100.00 / €100.00 / etc.

/// Pure rule engine: pick the most striking per-category spike vs the
/// previous period and turn it into a [DashboardInsight].
///
/// Inputs come from [DashboardSnapshot]; no IO. The use case never
/// fails — it returns `Right(null)` when no rule matched.
class GetDashboardInsightUseCase
    implements UseCase<DashboardInsight?, GetDashboardInsightParams> {
  const GetDashboardInsightUseCase();

  @override
  Future<Either<Failure, DashboardInsight?>> call(
    GetDashboardInsightParams params,
  ) async {
    return right(evaluate(params.snapshot));
  }

  /// Exposed for direct unit-testing (no `async`/`Either` ceremony).
  static DashboardInsight? evaluate(DashboardSnapshot snapshot) {
    if (snapshot.isEmpty) return null;

    DashboardInsight? best;
    double bestDelta = kInsightSpikeThresholdPercent;

    for (final MapEntry<int, int> entry
        in snapshot.byCategoryCurrent.entries) {
      final int currentMinor = entry.value;
      if (currentMinor < kInsightMinCurrentMinor) continue;

      final int previousMinor =
          snapshot.byCategoryPrevious[entry.key] ?? 0;
      // A category that didn't exist last period would yield infinite
      // delta — skip it; "first-time category" isn't actionable here.
      if (previousMinor == 0) continue;

      final double delta =
          ((currentMinor - previousMinor) / previousMinor) * 100.0;
      if (delta >= bestDelta) {
        bestDelta = delta;
        best = DashboardInsight(
          categoryId: entry.key,
          deltaPercent: delta,
          tone: DashboardInsightTone.warning,
        );
      }
    }

    return best;
  }
}

class GetDashboardInsightParams extends Equatable {
  const GetDashboardInsightParams({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  List<Object?> get props => <Object?>[snapshot];
}
