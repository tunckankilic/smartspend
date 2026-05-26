import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late int marketCategoryId;
  late int kahveCategoryId;

  setUp(() async {
    db = createTestDatabase();
    // Resolve seeded category IDs (insertion order — Market first).
    final List<Category> defaults = await db.categoryDao.getDefaults();
    marketCategoryId =
        defaults.firstWhere((Category c) => c.name == 'Market').id;
    kahveCategoryId =
        defaults.firstWhere((Category c) => c.name == 'Kahve').id;
  });
  tearDown(() async => db.close());

  Future<int> insertExpense({
    required int amount,
    required int categoryId,
    DateTime? date,
  }) {
    return db.expenseDao.insertExpense(
      ExpensesCompanion.insert(
        amount: amount,
        categoryId: categoryId,
        date: date ?? DateTime.utc(2026, 5, 15),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  group('ExpenseDao', () {
    test('insertExpense should mark pending_create', () async {
      final int id = await insertExpense(
        amount: 2500,
        categoryId: marketCategoryId,
      );
      final Expense? row = await db.expenseDao.getById(id);
      expect(row!.syncStatus, SyncStatus.pendingCreate);
      expect(row.amount, 2500);
    });

    test('getByDateRange should respect range bounds and ignore deletes',
        () async {
      await insertExpense(
        amount: 100,
        categoryId: marketCategoryId,
        date: DateTime.utc(2026, 5, 1),
      );
      final int midId = await insertExpense(
        amount: 200,
        categoryId: marketCategoryId,
        date: DateTime.utc(2026, 5, 15),
      );
      await insertExpense(
        amount: 300,
        categoryId: marketCategoryId,
        date: DateTime.utc(2026, 6, 10),
      );

      final List<Expense> midRange = await db.expenseDao.getByDateRange(
        DateTime.utc(2026, 5, 10),
        DateTime.utc(2026, 5, 31),
      );
      expect(midRange, hasLength(1));
      expect(midRange.first.id, midId);

      await db.expenseDao.softDeleteExpense(midId);
      final List<Expense> afterDelete = await db.expenseDao.getByDateRange(
        DateTime.utc(2026, 5, 10),
        DateTime.utc(2026, 5, 31),
      );
      expect(afterDelete, isEmpty);
    });

    test('getTotalByCategory should sum amounts by category', () async {
      await insertExpense(amount: 1000, categoryId: marketCategoryId);
      await insertExpense(amount: 1500, categoryId: marketCategoryId);
      await insertExpense(amount: 600, categoryId: kahveCategoryId);

      final Map<int, int> totals = await db.expenseDao.getTotalByCategory(
        DateTime.utc(2026, 5, 1),
        DateTime.utc(2026, 5, 31),
      );
      expect(totals[marketCategoryId], 2500);
      expect(totals[kahveCategoryId], 600);
    });

    test('getPendingSync should return all dirty rows', () async {
      await insertExpense(amount: 100, categoryId: marketCategoryId);
      final int second = await insertExpense(
        amount: 200,
        categoryId: kahveCategoryId,
      );
      await db.expenseDao.softDeleteExpense(second);

      final List<Expense> pending = await db.expenseDao.getPendingSync();
      expect(pending, hasLength(2));
      expect(
        pending.map((Expense e) => e.syncStatus).toSet(),
        <String>{SyncStatus.pendingCreate, SyncStatus.pendingDelete},
      );
    });
  });
}
