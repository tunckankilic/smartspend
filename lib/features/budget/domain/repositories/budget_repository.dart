import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';

/// Contract for the budget feature's data access.
///
/// Mirrors `ExpenseRepository`'s conventions: read-side calls return
/// from Drift unconditionally; write-side calls mutate Drift with a
/// `pending_*` sync status — the Sprint 8 sync engine pushes to
/// Supabase later.
abstract class BudgetRepository {
  /// Active budgets only (excludes soft-deleted + deactivated rows),
  /// ordered general-first then by category id.
  Future<Either<Failure, List<Budget>>> getActiveBudgets();

  /// Reactive variant — re-emits whenever the `budgets` table changes.
  /// The BudgetBloc subscribes to this so the page stays in sync with
  /// create/update/delete operations from any code path.
  Stream<List<Budget>> watchActiveBudgets();

  /// Insert a new budget. Returns the local Drift PK on success.
  ///
  /// [categoryId] = `null` means a general / total budget. The use case
  /// layer enforces "only one active general budget" + "only one
  /// active per category" before calling here.
  Future<Either<Failure, int>> createBudget({
    required int amountMinor,
    required BudgetPeriod period,
    required DateTime startDate,
    int? categoryId,
  });

  /// Patch fields on an existing budget. `null` means "leave unchanged".
  Future<Either<Failure, void>> updateBudget({
    required int id,
    int? amountMinor,
    BudgetPeriod? period,
    DateTime? startDate,
    bool? isActive,
  });

  /// Soft-delete — stamps `sync_status = 'pending_delete'`. The repo's
  /// own queries filter these out automatically.
  Future<Either<Failure, void>> deleteBudget(int id);
}
