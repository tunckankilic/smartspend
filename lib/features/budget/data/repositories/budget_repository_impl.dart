import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/daos/budget_dao.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';

/// Drift-backed [BudgetRepository] implementation.
///
/// Sprint 6 is local-only — every read returns from the `budgets` table
/// and every write stamps a `pending_*` sync status that Sprint 8 will
/// drain into Supabase. The `drift_db` alias keeps the generated
/// `Budget` row class from shadowing our domain `Budget` entity.
class BudgetRepositoryImpl implements BudgetRepository {
  const BudgetRepositoryImpl({required BudgetDao budgetDao})
      : _dao = budgetDao;

  final BudgetDao _dao;

  @override
  Future<Either<Failure, List<Budget>>> getActiveBudgets() async {
    try {
      final List<drift_db.Budget> rows = await _dao.getActive();
      return Right<Failure, List<Budget>>(rows.map(_toDomain).toList());
    } on Object catch (e) {
      return Left<Failure, List<Budget>>(
        CacheFailure(message: e.toString()),
      );
    }
  }

  @override
  Stream<List<Budget>> watchActiveBudgets() {
    return _dao
        .watchActive()
        .map((List<drift_db.Budget> rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<Either<Failure, int>> createBudget({
    required int amountMinor,
    required BudgetPeriod period,
    required DateTime startDate,
    int? categoryId,
  }) async {
    try {
      final DateTime nowUtc = DateTime.now().toUtc();
      final int id = await _dao.insertBudget(
        drift_db.BudgetsCompanion.insert(
          amount: amountMinor,
          period: period.name,
          startDate: startDate.toUtc(),
          updatedAt: nowUtc,
          categoryId: Value<int?>(categoryId),
          isActive: const Value<bool>(true),
        ),
      );
      return Right<Failure, int>(id);
    } on Object catch (e) {
      return Left<Failure, int>(CacheFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateBudget({
    required int id,
    int? amountMinor,
    BudgetPeriod? period,
    DateTime? startDate,
    bool? isActive,
  }) async {
    try {
      await _dao.updateBudget(
        id,
        drift_db.BudgetsCompanion(
          amount: amountMinor == null
              ? const Value<int>.absent()
              : Value<int>(amountMinor),
          period: period == null
              ? const Value<String>.absent()
              : Value<String>(period.name),
          startDate: startDate == null
              ? const Value<DateTime>.absent()
              : Value<DateTime>(startDate.toUtc()),
          isActive: isActive == null
              ? const Value<bool>.absent()
              : Value<bool>(isActive),
        ),
      );
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(CacheFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteBudget(int id) async {
    try {
      await _dao.softDeleteBudget(id);
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(CacheFailure(message: e.toString()));
    }
  }

  Budget _toDomain(drift_db.Budget row) {
    final BudgetPeriod period = BudgetPeriod.fromName(row.period) ??
        BudgetPeriod.monthly; // defensive fallback for legacy rows
    return Budget(
      id: row.id,
      amountMinor: row.amount,
      period: period,
      startDate: row.startDate,
      isActive: row.isActive,
      categoryId: row.categoryId,
      isPendingSync: SyncStatus.pending.contains(row.syncStatus),
    );
  }
}
