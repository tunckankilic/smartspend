import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'budget_dao.g.dart';

@DriftAccessor(tables: <Type>[Budgets, Expenses])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  Future<int> insertBudget(BudgetsCompanion entry) {
    return into(budgets).insert(
      entry.copyWith(
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        syncStatus: const Value<String>(SyncStatus.pendingCreate),
      ),
    );
  }

  Future<int> updateBudget(int id, BudgetsCompanion patch) {
    return (update(budgets)..where(($BudgetsTable t) => t.id.equals(id)))
        .write(
      patch.copyWith(
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        syncStatus: const Value<String>(SyncStatus.pendingUpdate),
      ),
    );
  }

  Future<int> softDeleteBudget(int id) {
    return (update(budgets)..where(($BudgetsTable t) => t.id.equals(id)))
        .write(
      BudgetsCompanion(
        syncStatus: const Value<String>(SyncStatus.pendingDelete),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
      ),
    );
  }

  Future<List<Budget>> getActive() {
    return (select(budgets)
          ..where(
            ($BudgetsTable t) =>
                t.isActive.equals(true) &
                t.syncStatus.equals(SyncStatus.pendingDelete).not(),
          )
          ..orderBy(<OrderClauseGenerator<$BudgetsTable>>[
            // General budgets (null category) first, then by category id.
            ($BudgetsTable t) => OrderingTerm.asc(t.categoryId),
            ($BudgetsTable t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// Reactive variant of [getActive] — re-emits whenever the `budgets`
  /// table changes. Powers [BudgetBloc]'s live snapshot.
  Stream<List<Budget>> watchActive() {
    return (select(budgets)
          ..where(
            ($BudgetsTable t) =>
                t.isActive.equals(true) &
                t.syncStatus.equals(SyncStatus.pendingDelete).not(),
          )
          ..orderBy(<OrderClauseGenerator<$BudgetsTable>>[
            ($BudgetsTable t) => OrderingTerm.asc(t.categoryId),
            ($BudgetsTable t) => OrderingTerm.asc(t.id),
          ]))
        .watch();
  }

  Future<Budget?> getById(int id) {
    return (select(budgets)
          ..where(($BudgetsTable t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<Budget>> getByCategory(int? categoryId) {
    return (select(budgets)
          ..where(
            ($BudgetsTable t) => categoryId == null
                ? t.categoryId.isNull()
                : t.categoryId.equals(categoryId),
          ))
        .get();
  }

  /// Returns whether the spent amount has reached [budget.amount].
  ///
  /// The caller passes the [spent] total — `BudgetDao` does not depend on
  /// [ExpenseDao] directly to keep the dependency graph flat.
  bool isExceeded(Budget budget, int spent) => spent >= budget.amount;

  Future<List<Budget>> getPendingSync() {
    return (select(budgets)
          ..where(
            ($BudgetsTable t) => t.syncStatus.isIn(SyncStatus.pending),
          ))
        .get();
  }
}
