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

  // ---------------------------------------------------------------------
  // Sprint 3 — list / filter / sort
  // ---------------------------------------------------------------------

  /// Apply the Sprint 3 filter knobs to a [select(expenses)] query.
  ///
  /// Always excludes soft-deleted rows. `searchQuery` is intentionally
  /// **not** applied here — the repository runs the substring match in
  /// Dart so it can also score against the joined `receipts.store_name`
  /// without a complex SQL join. See [ExpenseRepositoryImpl].
  SimpleSelectStatement<$ExpensesTable, Expense> _buildFiltered({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    ExpenseDaoSort sort = ExpenseDaoSort.dateDesc,
  }) {
    final SimpleSelectStatement<$ExpensesTable, Expense> q = select(expenses)
      ..where(
        ($ExpensesTable t) =>
            t.syncStatus.equals(SyncStatus.pendingDelete).not(),
      );

    if (dateFrom != null) {
      q.where(($ExpensesTable t) => t.date.isBiggerOrEqualValue(dateFrom));
    }
    if (dateTo != null) {
      q.where(($ExpensesTable t) => t.date.isSmallerOrEqualValue(dateTo));
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      q.where(($ExpensesTable t) => t.categoryId.isIn(categoryIds.toList()));
    }
    if (minAmount != null) {
      q.where(($ExpensesTable t) => t.amount.isBiggerOrEqualValue(minAmount));
    }
    if (maxAmount != null) {
      q.where(($ExpensesTable t) => t.amount.isSmallerOrEqualValue(maxAmount));
    }

    switch (sort) {
      case ExpenseDaoSort.dateDesc:
        q.orderBy(<OrderClauseGenerator<$ExpensesTable>>[
          ($ExpensesTable t) =>
              OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ($ExpensesTable t) =>
              OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ]);
      case ExpenseDaoSort.dateAsc:
        q.orderBy(<OrderClauseGenerator<$ExpensesTable>>[
          ($ExpensesTable t) =>
              OrderingTerm(expression: t.date),
          ($ExpensesTable t) =>
              OrderingTerm(expression: t.id),
        ]);
      case ExpenseDaoSort.amountDesc:
        q.orderBy(<OrderClauseGenerator<$ExpensesTable>>[
          ($ExpensesTable t) =>
              OrderingTerm(expression: t.amount, mode: OrderingMode.desc),
          ($ExpensesTable t) =>
              OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        ]);
      case ExpenseDaoSort.amountAsc:
        q.orderBy(<OrderClauseGenerator<$ExpensesTable>>[
          ($ExpensesTable t) => OrderingTerm(expression: t.amount),
          ($ExpensesTable t) =>
              OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        ]);
    }
    return q;
  }

  /// Snapshot of expenses matching the predicate set.
  Future<List<Expense>> queryFiltered({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    ExpenseDaoSort sort = ExpenseDaoSort.dateDesc,
  }) {
    return _buildFiltered(
      dateFrom: dateFrom,
      dateTo: dateTo,
      categoryIds: categoryIds,
      minAmount: minAmount,
      maxAmount: maxAmount,
      sort: sort,
    ).get();
  }

  /// Reactive variant — re-fires whenever any row in `expenses` changes.
  ///
  /// Drift filters by table dependencies, so unrelated tables won't
  /// cause spurious emissions. The repository layers a category-change
  /// stream on top to refresh joined labels.
  Stream<List<Expense>> watchFiltered({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    ExpenseDaoSort sort = ExpenseDaoSort.dateDesc,
  }) {
    return _buildFiltered(
      dateFrom: dateFrom,
      dateTo: dateTo,
      categoryIds: categoryIds,
      minAmount: minAmount,
      maxAmount: maxAmount,
      sort: sort,
    ).watch();
  }
}

/// Sort orders accepted by [ExpenseDao.queryFiltered] /
/// [ExpenseDao.watchFiltered]. Kept inside the data layer so the
/// domain-level [ExpenseSortOrder] doesn't leak Drift types.
enum ExpenseDaoSort { dateDesc, dateAsc, amountDesc, amountAsc }
