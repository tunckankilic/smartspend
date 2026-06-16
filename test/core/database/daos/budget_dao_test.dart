import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late int marketCategoryId;

  setUp(() async {
    db = createTestDatabase();
    final List<Category> defaults = await db.categoryDao.getDefaults();
    marketCategoryId =
        defaults.firstWhere((Category c) => c.name == 'Market').id;
  });
  tearDown(() async => db.close());

  Future<int> insertBudget({
    int amount = 100000,
    int? categoryId,
    bool isActive = true,
  }) {
    return db.budgetDao.insertBudget(
      BudgetsCompanion.insert(
        userId: const Value<String?>('user-1'),
        categoryId: Value<int?>(categoryId),
        amount: amount,
        period: 'monthly',
        startDate: DateTime.utc(2026, 5, 1),
        isActive: Value<bool>(isActive),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  group('BudgetDao', () {
    test('insertBudget should mark pending_create', () async {
      final int id = await insertBudget(categoryId: marketCategoryId);
      final List<Budget> all = await db.budgetDao.getActive();
      final Budget row = all.firstWhere((Budget b) => b.id == id);
      expect(row.syncStatus, SyncStatus.pendingCreate);
      expect(row.amount, 100000);
    });

    test('getActive should exclude inactive and soft-deleted budgets',
        () async {
      await insertBudget(categoryId: marketCategoryId);
      final int inactiveId =
          await insertBudget(categoryId: marketCategoryId, isActive: false);
      final int deletedId = await insertBudget(categoryId: marketCategoryId);
      await db.budgetDao.softDeleteBudget(deletedId);

      final List<Budget> active = await db.budgetDao.getActive();
      expect(active, hasLength(1));
      expect(active.first.id, isNot(inactiveId));
      expect(active.first.id, isNot(deletedId));
    });

    test('getByCategory(null) should return general budgets only', () async {
      await insertBudget(categoryId: marketCategoryId);
      await insertBudget();

      final List<Budget> general = await db.budgetDao.getByCategory(null);
      expect(general, hasLength(1));
      expect(general.first.categoryId, isNull);
    });

    test('isExceeded should be true at or above amount', () async {
      await insertBudget(amount: 50000, categoryId: marketCategoryId);
      final Budget budget = (await db.budgetDao.getActive()).single;
      expect(db.budgetDao.isExceeded(budget, 49999), isFalse);
      expect(db.budgetDao.isExceeded(budget, 50000), isTrue);
      expect(db.budgetDao.isExceeded(budget, 60000), isTrue);
    });
  });
}
