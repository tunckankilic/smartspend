// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/data/datasources/expense_local_data_source.dart';
import 'package:smartspend/features/expenses/data/models/expense_model.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';

/// Drift-backed [ExpenseRepository].
///
/// Sprint 3 contract:
/// * **Reads** always hit Drift (offline-first); they never touch
///   Supabase. The sync worker (Sprint 8) keeps Drift fresh in the
///   background.
/// * **Writes** mutate Drift and stamp `sync_status = pending_*`. The
///   sync worker picks them up later.
///
/// Search (`note` + `receipts.store_name` substring) is applied in-Dart
/// after the DAO-level filter so we don't need a SQL join. Reasonable
/// for portfolio-scale data; Sprint 9 will revisit if profiling shows
/// hotspots.
class ExpenseRepositoryImpl implements ExpenseRepository {
  const ExpenseRepositoryImpl({
    required ExpenseLocalDataSource localDataSource,
    String fallbackCurrency = 'TRY',
  })  : _local = localDataSource,
        _fallbackCurrency = fallbackCurrency;

  final ExpenseLocalDataSource _local;
  final String _fallbackCurrency;

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, List<Expense>>> getExpenses(
    ExpenseFilter filter,
  ) async {
    try {
      final List<Expense> domain = await _loadFiltered(filter);
      return Right<Failure, List<Expense>>(domain);
    } on Object catch (e) {
      return Left<Failure, List<Expense>>(
        CacheFailure(message: 'getExpenses failed: $e'),
      );
    }
  }

  @override
  Stream<List<Expense>> watchExpenses(ExpenseFilter filter) {
    final Stream<List<drift_db.Expense>> raw = _local.watchExpenses(
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
      categoryIds: filter.categoryIds,
      minAmount: filter.minAmount,
      maxAmount: filter.maxAmount,
      sort: _toDaoSort(filter.sortOrder),
    );
    return raw.asyncMap((List<drift_db.Expense> rows) async {
      return _materialize(rows, filter);
    });
  }

  @override
  Future<Either<Failure, Expense?>> getExpenseById(int id) async {
    try {
      final drift_db.Expense? row = await _local.getById(id);
      if (row == null) return const Right<Failure, Expense?>(null);
      final List<Expense> materialized =
          await _materialize(<drift_db.Expense>[row], ExpenseFilter.empty);
      return Right<Failure, Expense?>(
        materialized.isEmpty ? null : materialized.first,
      );
    } on Object catch (e) {
      return Left<Failure, Expense?>(
        CacheFailure(message: 'getExpenseById failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, ExpenseSummary>> getSummary(
    ExpenseFilter filter,
  ) async {
    try {
      final List<Expense> rows = await _loadFiltered(filter);
      if (rows.isEmpty) {
        return Right<Failure, ExpenseSummary>(
          ExpenseSummary.empty.copyWithCurrency(_fallbackCurrency),
        );
      }
      int total = 0;
      final Map<int, int> byCat = <int, int>{};
      final Map<String, int> currencyCounts = <String, int>{};
      for (final Expense e in rows) {
        total += e.amount;
        byCat.update(
          e.category.id,
          (int prev) => prev + e.amount,
          ifAbsent: () => e.amount,
        );
        currencyCounts.update(
          e.currency,
          (int prev) => prev + 1,
          ifAbsent: () => 1,
        );
      }
      final String dominant = currencyCounts.entries
          .reduce(
            (MapEntry<String, int> a, MapEntry<String, int> b) =>
                a.value >= b.value ? a : b,
          )
          .key;
      return Right<Failure, ExpenseSummary>(
        ExpenseSummary(
          totalMinor: total,
          currency: dominant,
          byCategory: byCat,
          count: rows.length,
        ),
      );
    } on Object catch (e) {
      return Left<Failure, ExpenseSummary>(
        CacheFailure(message: 'getSummary failed: $e'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  @override
  Future<Either<Failure, int>> addExpense({
    required int amount,
    required int categoryId,
    required DateTime date,
    required bool isManual,
    String? note,
    int? receiptId,
    bool isRecurring = false,
    String? recurringPeriod,
    List<String> tags = const <String>[],
  }) async {
    try {
      if (amount <= 0) {
        return const Left<Failure, int>(
          CacheFailure(message: 'amount must be positive', code: 'amount_zero'),
        );
      }
      final drift_db.ExpensesCompanion entry =
          drift_db.ExpensesCompanion.insert(
        amount: amount,
        categoryId: categoryId,
        date: date.toUtc(),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        receiptId: Value<int?>(receiptId),
        note: Value<String?>(note),
        isManual: Value<bool>(isManual),
        isRecurring: Value<bool>(isRecurring),
        recurringPeriod: Value<String?>(recurringPeriod),
      );
      final int id = await _local.insertExpense(entry);
      if (tags.isNotEmpty) {
        await _local.syncTagsForExpense(id, tags);
      }
      return Right<Failure, int>(id);
    } on Object catch (e) {
      return Left<Failure, int>(
        CacheFailure(message: 'addExpense failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, void>> updateExpense({
    required int id,
    int? amount,
    int? categoryId,
    DateTime? date,
    String? note,
    bool clearNote = false,
    bool? isRecurring,
    String? recurringPeriod,
    bool clearRecurringPeriod = false,
    List<String>? tags,
  }) async {
    try {
      if (amount != null && amount <= 0) {
        return const Left<Failure, void>(
          CacheFailure(message: 'amount must be positive', code: 'amount_zero'),
        );
      }
      final drift_db.ExpensesCompanion patch = buildExpensePatch(
        amount: amount,
        categoryId: categoryId,
        date: date?.toUtc(),
        note: note,
        clearNote: clearNote,
        isRecurring: isRecurring,
        recurringPeriod: recurringPeriod,
        clearRecurringPeriod: clearRecurringPeriod,
      );
      await _local.updateExpense(id, patch);
      if (tags != null) {
        await _local.syncTagsForExpense(id, tags);
      }
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(
        CacheFailure(message: 'updateExpense failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, List<String>>> getAllTagNames() async {
    try {
      final List<String> names = await _local.getAllTagNames();
      return Right<Failure, List<String>>(names);
    } on Object catch (e) {
      return Left<Failure, List<String>>(
        CacheFailure(message: 'getAllTagNames failed: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, void>> deleteExpense(int id) async {
    try {
      await _local.softDeleteExpense(id);
      return const Right<Failure, void>(null);
    } on Object catch (e) {
      return Left<Failure, void>(
        CacheFailure(message: 'deleteExpense failed: $e'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<List<Expense>> _loadFiltered(ExpenseFilter filter) async {
    final List<drift_db.Expense> rows = await _local.queryExpenses(
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
      categoryIds: filter.categoryIds,
      minAmount: filter.minAmount,
      maxAmount: filter.maxAmount,
      sort: _toDaoSort(filter.sortOrder),
    );
    return _materialize(rows, filter);
  }

  /// Joins Drift rows to category + receipt metadata and applies the
  /// in-Dart search filter.
  Future<List<Expense>> _materialize(
    List<drift_db.Expense> rows,
    ExpenseFilter filter,
  ) async {
    if (rows.isEmpty) return const <Expense>[];

    final List<drift_db.Category> catRows = await _local.getAllCategories();
    final Map<int, Category> categories = <int, Category>{
      for (final drift_db.Category c in catRows)
        c.id: Category(
          id: c.id,
          name: c.name,
          icon: c.icon,
          color: c.color,
          isCustom: c.isCustom,
        ),
    };

    final List<int> receiptIds = rows
        .map((drift_db.Expense e) => e.receiptId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final List<drift_db.Receipt> receipts =
        await _local.getReceiptsByIds(receiptIds);
    final Map<int, drift_db.Receipt> receiptIndex = <int, drift_db.Receipt>{
      for (final drift_db.Receipt r in receipts) r.id: r,
    };

    // Tags — single batched lookup for the visible window.
    final List<int> expenseIds =
        rows.map((drift_db.Expense e) => e.id).toList(growable: false);
    final Map<int, List<String>> tagsByExpense =
        await _local.getTagsForExpenseIds(expenseIds);

    final String query = filter.searchQuery.trim().toLowerCase();

    final List<Expense> out = <Expense>[];
    for (final drift_db.Expense row in rows) {
      final Category? category = categories[row.categoryId];
      if (category == null) {
        // Defensive: an expense referencing a missing category shouldn't
        // happen with our FK, but if it does, fall back to a neutral
        // placeholder so the row is still visible.
        continue;
      }
      final drift_db.Receipt? receipt =
          row.receiptId == null ? null : receiptIndex[row.receiptId];
      final String currency = receipt?.currency ?? _fallbackCurrency;

      if (query.isNotEmpty) {
        final String note = (row.note ?? '').toLowerCase();
        final String store = (receipt?.storeName ?? '').toLowerCase();
        if (!note.contains(query) && !store.contains(query)) {
          continue;
        }
      }

      out.add(
        ExpenseModel.fromDriftRow(
          row,
          category: category,
          currency: currency,
          tags: tagsByExpense[row.id] ?? const <String>[],
        ),
      );
    }
    return out;
  }

  ExpenseDaoSort _toDaoSort(ExpenseSortOrder order) {
    switch (order) {
      case ExpenseSortOrder.dateDesc:
        return ExpenseDaoSort.dateDesc;
      case ExpenseSortOrder.dateAsc:
        return ExpenseDaoSort.dateAsc;
      case ExpenseSortOrder.amountDesc:
        return ExpenseDaoSort.amountDesc;
      case ExpenseSortOrder.amountAsc:
        return ExpenseDaoSort.amountAsc;
    }
  }
}

extension on ExpenseSummary {
  /// Returns a copy of this summary with [currency] swapped in. Used by
  /// the empty-result branch so we don't surface "TRY" when the user is
  /// on EUR.
  ExpenseSummary copyWithCurrency(String currency) {
    return ExpenseSummary(
      totalMinor: totalMinor,
      currency: currency,
      byCategory: byCategory,
      count: count,
    );
  }
}
