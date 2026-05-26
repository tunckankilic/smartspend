import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'expense_dao.g.dart';

@DriftAccessor(tables: <Type>[Expenses])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  Future<int> insertExpense(ExpensesCompanion entry) {
    final DateTime now = DateTime.now().toUtc();
    return into(expenses).insert(
      entry.copyWith(
        createdAt: Value<DateTime>(now),
        updatedAt: Value<DateTime>(now),
        syncStatus: const Value<String>(SyncStatus.pendingCreate),
      ),
    );
  }

  Future<int> updateExpense(int id, ExpensesCompanion patch) {
    return (update(expenses)..where(($ExpensesTable t) => t.id.equals(id)))
        .write(
      patch.copyWith(
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        syncStatus: const Value<String>(SyncStatus.pendingUpdate),
      ),
    );
  }

  Future<int> softDeleteExpense(int id) {
    return (update(expenses)..where(($ExpensesTable t) => t.id.equals(id)))
        .write(
      ExpensesCompanion(
        syncStatus: const Value<String>(SyncStatus.pendingDelete),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
      ),
    );
  }

  Future<int> hardDeleteExpense(int id) {
    return (delete(expenses)..where(($ExpensesTable t) => t.id.equals(id)))
        .go();
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  Future<Expense?> getById(int id) {
    return (select(expenses)..where(($ExpensesTable t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<Expense>> getByDateRange(DateTime from, DateTime to) {
    return (select(expenses)
          ..where(
            ($ExpensesTable t) =>
                t.date.isBetweenValues(from, to) &
                t.syncStatus.equals(SyncStatus.pendingDelete).not(),
          )
          ..orderBy(<OrderClauseGenerator<$ExpensesTable>>[
            ($ExpensesTable t) =>
                OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<List<Expense>> getByCategory(int categoryId) {
    return (select(expenses)
          ..where(
            ($ExpensesTable t) =>
                t.categoryId.equals(categoryId) &
                t.syncStatus.equals(SyncStatus.pendingDelete).not(),
          ))
        .get();
  }

  /// Sum of expense amounts grouped by category between [from] and [to].
  ///
  /// Returns category-id → total (in minor units). Soft-deleted rows are
  /// excluded.
  Future<Map<int, int>> getTotalByCategory(DateTime from, DateTime to) async {
    final Expression<int> sumExpr = expenses.amount.sum().cast<int>();
    final JoinedSelectStatement<HasResultSet, dynamic> q = selectOnly(expenses)
      ..addColumns(<Expression<Object>>[expenses.categoryId, sumExpr])
      ..where(
        expenses.date.isBetweenValues(from, to) &
            expenses.syncStatus.equals(SyncStatus.pendingDelete).not(),
      )
      ..groupBy(<Expression<Object>>[expenses.categoryId]);

    final List<TypedResult> rows = await q.get();
    return <int, int>{
      for (final TypedResult r in rows)
        r.read(expenses.categoryId)!: r.read(sumExpr) ?? 0,
    };
  }

  /// Sum of expense amounts grouped by date (day granularity, UTC).
  Future<Map<DateTime, int>> getDailyTotals(DateTime from, DateTime to) async {
    final List<Expense> rows = await getByDateRange(from, to);
    final Map<DateTime, int> totals = <DateTime, int>{};
    for (final Expense e in rows) {
      final DateTime day = DateTime.utc(e.date.year, e.date.month, e.date.day);
      totals[day] = (totals[day] ?? 0) + e.amount;
    }
    return totals;
  }

  Future<List<Expense>> getPendingSync() {
    return (select(expenses)
          ..where(
            ($ExpensesTable t) => t.syncStatus.isIn(SyncStatus.pending),
          ))
        .get();
  }
}
