import 'package:drift/drift.dart' show Value;

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/daos/expense_dao.dart';
import 'package:smartspend/core/database/daos/receipt_dao.dart';
import 'package:smartspend/core/database/daos/tag_dao.dart';

/// Thin wrapper over the Drift DAOs used by the expenses feature.
///
/// Per CLAUDE.md, the repository must not run raw SQL — it goes through a
/// DAO. This datasource exists so the repository can mock a single
/// dependency in tests instead of three DAOs at once.
abstract class ExpenseLocalDataSource {
  /// Snapshot fetch with the Sprint 3 filter knobs applied at the SQL
  /// level. Search across `note` / store name is layered on top by the
  /// repository in Dart.
  Future<List<drift_db.Expense>> queryExpenses({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    ExpenseDaoSort sort,
  });

  /// Same predicates as [queryExpenses], reactive flavor.
  Stream<List<drift_db.Expense>> watchExpenses({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    ExpenseDaoSort sort,
  });

  Future<drift_db.Expense?> getById(int id);

  /// All categories — used for the in-memory join when building domain
  /// [Expense] objects. The repository caches this between reads.
  Future<List<drift_db.Category>> getAllCategories();

  /// Receipts matching [ids]. Used to attach currency + store name to
  /// scan-flow expenses without an SQL join.
  Future<List<drift_db.Receipt>> getReceiptsByIds(List<int> ids);

  Future<int> insertExpense(drift_db.ExpensesCompanion entry);

  Future<int> updateExpense(int id, drift_db.ExpensesCompanion patch);

  /// Soft delete — flips the row to `pending_delete`.
  Future<int> softDeleteExpense(int id);

  /// Resolve / create each [tagNames] entry and attach the resulting set
  /// to [expenseId]. Empty input clears all tags on the expense.
  Future<void> syncTagsForExpense(int expenseId, List<String> tagNames);

  /// Tags currently linked to [expenseId], sorted alphabetically by name.
  Future<List<String>> getTagsForExpense(int expenseId);

  /// Batched lookup — `expenseId → sorted tag names`.
  Future<Map<int, List<String>>> getTagsForExpenseIds(List<int> ids);

  /// All tag names a user has typed, sorted alphabetically.
  Future<List<String>> getAllTagNames();
}

class ExpenseLocalDataSourceImpl implements ExpenseLocalDataSource {
  const ExpenseLocalDataSourceImpl({
    required ExpenseDao expenseDao,
    required CategoryDao categoryDao,
    required ReceiptDao receiptDao,
    required TagDao tagDao,
  })  : _expenses = expenseDao,
        _categories = categoryDao,
        _receipts = receiptDao,
        _tags = tagDao;

  final ExpenseDao _expenses;
  final CategoryDao _categories;
  final ReceiptDao _receipts;
  final TagDao _tags;

  @override
  Future<List<drift_db.Expense>> queryExpenses({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    ExpenseDaoSort sort = ExpenseDaoSort.dateDesc,
  }) {
    return _expenses.queryFiltered(
      dateFrom: dateFrom,
      dateTo: dateTo,
      categoryIds: categoryIds,
      minAmount: minAmount,
      maxAmount: maxAmount,
      sort: sort,
    );
  }

  @override
  Stream<List<drift_db.Expense>> watchExpenses({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    ExpenseDaoSort sort = ExpenseDaoSort.dateDesc,
  }) {
    return _expenses.watchFiltered(
      dateFrom: dateFrom,
      dateTo: dateTo,
      categoryIds: categoryIds,
      minAmount: minAmount,
      maxAmount: maxAmount,
      sort: sort,
    );
  }

  @override
  Future<drift_db.Expense?> getById(int id) => _expenses.getById(id);

  @override
  Future<List<drift_db.Category>> getAllCategories() => _categories.getAll();

  @override
  Future<List<drift_db.Receipt>> getReceiptsByIds(List<int> ids) async {
    if (ids.isEmpty) return <drift_db.Receipt>[];
    // ReceiptDao doesn't ship a bulk-by-id call yet; do a per-id lookup
    // through getById. The hot path is small (one receipt per scan-flow
    // expense in the visible window) so this is acceptable until
    // Sprint 5 adds a proper batched query.
    final List<drift_db.Receipt> out = <drift_db.Receipt>[];
    for (final int id in ids) {
      final drift_db.Receipt? r = await _receipts.getById(id);
      if (r != null) out.add(r);
    }
    return out;
  }

  @override
  Future<int> insertExpense(drift_db.ExpensesCompanion entry) {
    return _expenses.insertExpense(entry);
  }

  @override
  Future<int> updateExpense(int id, drift_db.ExpensesCompanion patch) {
    return _expenses.updateExpense(id, patch);
  }

  @override
  Future<int> softDeleteExpense(int id) => _expenses.softDeleteExpense(id);

  @override
  Future<void> syncTagsForExpense(
    int expenseId,
    List<String> tagNames,
  ) async {
    await _tags.resolveAndAttach(expenseId, tagNames);
  }

  @override
  Future<List<String>> getTagsForExpense(int expenseId) async {
    final List<drift_db.Tag> rows = await _tags.getForExpense(expenseId);
    final List<String> names = rows
        .map((drift_db.Tag t) => t.name)
        .toList(growable: false)
      ..sort((String a, String b) =>
          a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  @override
  Future<Map<int, List<String>>> getTagsForExpenseIds(List<int> ids) {
    return _tags.getTagsForExpenseIds(ids);
  }

  @override
  Future<List<String>> getAllTagNames() async {
    final List<drift_db.Tag> rows = await _tags.getAll();
    return rows
        .map((drift_db.Tag t) => t.name)
        .toList(growable: false);
  }
}

/// Helper to build a partial companion when only a subset of columns is
/// changing. Kept here so the repository doesn't import `package:drift`.
drift_db.ExpensesCompanion buildExpensePatch({
  int? amount,
  int? categoryId,
  DateTime? date,
  String? note,
  bool clearNote = false,
  bool? isRecurring,
  String? recurringPeriod,
  bool clearRecurringPeriod = false,
}) {
  return drift_db.ExpensesCompanion(
    amount: amount == null ? const Value<int>.absent() : Value<int>(amount),
    categoryId: categoryId == null
        ? const Value<int>.absent()
        : Value<int>(categoryId),
    date: date == null
        ? const Value<DateTime>.absent()
        : Value<DateTime>(date),
    note: clearNote
        ? const Value<String?>(null)
        : (note == null
            ? const Value<String?>.absent()
            : Value<String?>(note)),
    isRecurring: isRecurring == null
        ? const Value<bool>.absent()
        : Value<bool>(isRecurring),
    recurringPeriod: clearRecurringPeriod
        ? const Value<String?>(null)
        : (recurringPeriod == null
            ? const Value<String?>.absent()
            : Value<String?>(recurringPeriod)),
  );
}
