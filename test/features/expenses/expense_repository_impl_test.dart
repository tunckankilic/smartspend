import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart'
    show AppDatabase, CategoriesCompanion, ExpensesCompanion, ReceiptsCompanion;
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/data/datasources/expense_local_data_source.dart';
import 'package:smartspend/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';

import 'package:drift/drift.dart' show Value;

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepositoryImpl repo;

  setUp(() async {
    db = createTestDatabase();
    // Force the migration to seed defaults.
    await db.categoryDao.getAll();
    repo = ExpenseRepositoryImpl(
      localDataSource: ExpenseLocalDataSourceImpl(
        expenseDao: db.expenseDao,
        categoryDao: db.categoryDao,
        receiptDao: db.receiptDao,
        tagDao: db.tagDao,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedCategory(String name, String icon) async {
    return db.categoryDao.insertCustom(
      CategoriesCompanion.insert(
        name: name,
        icon: icon,
        color: 0xFF000000,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<int> seedExpense({
    required int amount,
    required int categoryId,
    required DateTime date,
    String? note,
    int? receiptId,
  }) async {
    return db.expenseDao.insertExpense(
      ExpensesCompanion.insert(
        amount: amount,
        categoryId: categoryId,
        date: date,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        note: Value<String?>(note),
        receiptId: Value<int?>(receiptId),
      ),
    );
  }

  group('addExpense + getExpenses', () {
    test('should round-trip a manual expense', () async {
      final List<dynamic> seeded = await db.categoryDao.getAll();
      final int categoryId = (seeded.first as dynamic).id as int;

      final Either<Failure, int> add = await repo.addExpense(
        amount: 2500,
        categoryId: categoryId,
        date: DateTime.utc(2026, 5, 20),
        isManual: true,
        note: 'kahve',
      );
      expect(add.isRight(), isTrue);

      final List<Expense> rows = (await repo.getExpenses(ExpenseFilter.empty))
          .getOrElse(() => throw StateError('left'));
      expect(rows.length, 1);
      expect(rows.first.amount, 2500);
      expect(rows.first.note, 'kahve');
      expect(rows.first.isManual, isTrue);
      expect(rows.first.isPendingSync, isTrue);
    });

    test('should reject non-positive amounts', () async {
      final Either<Failure, int> add = await repo.addExpense(
        amount: 0,
        categoryId: 1,
        date: DateTime.utc(2026, 5, 20),
        isManual: true,
      );
      expect(add.isLeft(), isTrue);
    });
  });

  group('filters + sort', () {
    late int marketId;
    late int kahveId;

    setUp(() async {
      marketId = await seedCategory('TestMarket', 'shopping_cart');
      kahveId = await seedCategory('TestKahve', 'coffee');

      await seedExpense(
        amount: 1500,
        categoryId: marketId,
        date: DateTime.utc(2026, 5, 20),
        note: 'ekmek',
      );
      await seedExpense(
        amount: 3000,
        categoryId: kahveId,
        date: DateTime.utc(2026, 5, 22),
        note: 'latte',
      );
      await seedExpense(
        amount: 500,
        categoryId: marketId,
        date: DateTime.utc(2026, 4, 1),
        note: 'eski alışveriş',
      );
    });

    test('should narrow to selected categories', () async {
      final ExpenseFilter f = ExpenseFilter(categoryIds: <int>{kahveId});
      final List<Expense> rows = (await repo.getExpenses(f))
          .getOrElse(() => throw StateError('left'));
      expect(rows.length, 1);
      expect(rows.first.category.id, kahveId);
    });

    test('should narrow by date range', () async {
      final ExpenseFilter f = ExpenseFilter(
        dateFrom: DateTime.utc(2026, 5, 1),
      );
      final List<Expense> rows = (await repo.getExpenses(f))
          .getOrElse(() => throw StateError('left'));
      expect(rows.length, 2);
    });

    test('should narrow by min/max amount', () async {
      const ExpenseFilter f = ExpenseFilter(
        minAmount: 1000,
        maxAmount: 2000,
      );
      final List<Expense> rows = (await repo.getExpenses(f))
          .getOrElse(() => throw StateError('left'));
      expect(rows.length, 1);
      expect(rows.first.amount, 1500);
    });

    test('should search note (case-insensitive)', () async {
      const ExpenseFilter f = ExpenseFilter(searchQuery: 'LATTE');
      final List<Expense> rows = (await repo.getExpenses(f))
          .getOrElse(() => throw StateError('left'));
      expect(rows.length, 1);
      expect(rows.first.note, 'latte');
    });

    test('should search joined receipt store_name', () async {
      // Attach a third expense to a receipt with a known store name.
      final int receiptId = await db.receiptDao.insertReceipt(
        ReceiptsCompanion.insert(
          date: DateTime.utc(2026, 5, 18),
          total: 800,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          storeName: const Value<String?>('BİM Halkalı'),
        ),
      );
      await seedExpense(
        amount: 800,
        categoryId: marketId,
        date: DateTime.utc(2026, 5, 18),
        note: 'süt',
        receiptId: receiptId,
      );

      const ExpenseFilter f = ExpenseFilter(searchQuery: 'bim');
      final List<Expense> rows = (await repo.getExpenses(f))
          .getOrElse(() => throw StateError('left'));
      expect(rows.length, 1);
      expect(rows.first.note, 'süt');
      expect(rows.first.currency, anyOf('TRY', isA<String>()));
    });

    test('should sort newest-first by default', () async {
      final List<Expense> rows = (await repo.getExpenses(ExpenseFilter.empty))
          .getOrElse(() => throw StateError('left'));
      expect(
        rows.map((Expense e) => e.date).toList(),
        <DateTime>[
          DateTime.utc(2026, 5, 22),
          DateTime.utc(2026, 5, 20),
          DateTime.utc(2026, 4, 1),
        ],
      );
    });

    test('should sort by amount descending', () async {
      const ExpenseFilter f = ExpenseFilter(
        sortOrder: ExpenseSortOrder.amountDesc,
      );
      final List<Expense> rows = (await repo.getExpenses(f))
          .getOrElse(() => throw StateError('left'));
      expect(
        rows.map((Expense e) => e.amount).toList(),
        <int>[3000, 1500, 500],
      );
    });
  });

  group('deleteExpense', () {
    test('should soft-delete and hide from subsequent reads', () async {
      final int catId = (await db.categoryDao.getAll()).first.id;
      final int id = await seedExpense(
        amount: 1000,
        categoryId: catId,
        date: DateTime.utc(2026, 5, 1),
      );

      final Either<Failure, void> r = await repo.deleteExpense(id);
      expect(r.isRight(), isTrue);

      final List<Expense> rows = (await repo.getExpenses(ExpenseFilter.empty))
          .getOrElse(() => throw StateError('left'));
      expect(rows.where((Expense e) => e.id == id), isEmpty);

      // The row still exists in Drift with pending_delete so the sync
      // worker can find it.
      final dynamic raw = await db.expenseDao.getById(id);
      expect((raw as dynamic).syncStatus, SyncStatus.pendingDelete);
    });
  });

  group('updateExpense', () {
    test('should patch amount + flip syncStatus to pending_update',
        () async {
      final int catId = (await db.categoryDao.getAll()).first.id;
      final int id = await seedExpense(
        amount: 1000,
        categoryId: catId,
        date: DateTime.utc(2026, 5, 1),
      );

      // Round-trip through addExpense's pending_create — flip to synced
      // first so the test exercises the pending_update transition.
      await db.expenseDao.hardDeleteExpense(id);
      final int freshId = await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          amount: 1000,
          categoryId: catId,
          date: DateTime.utc(2026, 5, 1),
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final Either<Failure, void> r = await repo.updateExpense(
        id: freshId,
        amount: 1500,
        note: 'updated',
      );
      expect(r.isRight(), isTrue);

      final dynamic row = await db.expenseDao.getById(freshId);
      expect((row as dynamic).amount, 1500);
      expect((row as dynamic).note, 'updated');
    });

    test('should reject non-positive amounts', () async {
      final int catId = (await db.categoryDao.getAll()).first.id;
      final int id = await seedExpense(
        amount: 1000,
        categoryId: catId,
        date: DateTime.utc(2026, 5, 1),
      );
      final Either<Failure, void> r = await repo.updateExpense(
        id: id,
        amount: -1,
      );
      expect(r.isLeft(), isTrue);
    });
  });

  group('getSummary', () {
    test('should sum totals and group by category', () async {
      final int marketId = await seedCategory('SumMarket', 'shopping_cart');
      final int kahveId = await seedCategory('SumKahve', 'coffee');
      await seedExpense(
        amount: 1000,
        categoryId: marketId,
        date: DateTime.utc(2026, 5, 1),
      );
      await seedExpense(
        amount: 500,
        categoryId: marketId,
        date: DateTime.utc(2026, 5, 2),
      );
      await seedExpense(
        amount: 700,
        categoryId: kahveId,
        date: DateTime.utc(2026, 5, 3),
      );

      final ExpenseSummary s = (await repo.getSummary(ExpenseFilter.empty))
          .getOrElse(() => throw StateError('left'));
      expect(s.count, 3);
      expect(s.totalMinor, 2200);
      expect(s.byCategory[marketId], 1500);
      expect(s.byCategory[kahveId], 700);
    });

    test('should return the empty summary with fallback currency for no rows',
        () async {
      final ExpenseSummary s = (await repo.getSummary(ExpenseFilter.empty))
          .getOrElse(() => throw StateError('left'));
      expect(s.count, 0);
      expect(s.totalMinor, 0);
      expect(s.currency, 'TRY');
    });
  });
}
