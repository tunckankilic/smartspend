import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/default_categories.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  group('CategoryDao', () {
    test('should seed all 15 default categories on first launch', () async {
      final List<Category> defaults = await db.categoryDao.getDefaults();
      expect(defaults, hasLength(kDefaultCategories.length));
      expect(
        defaults.map((Category c) => c.name).toSet(),
        kDefaultCategories
            .map((DefaultCategoryDefinition c) => c.name)
            .toSet(),
      );
      // Defaults must not be flagged as custom.
      expect(defaults.every((Category c) => !c.isCustom), isTrue);
      // Defaults must have NULL userId (global).
      expect(defaults.every((Category c) => c.userId == null), isTrue);
    });

    test('should insert a custom category as pending_create', () async {
      const String userId = 'user-abc';
      final int id = await db.categoryDao.insertCustom(
        CategoriesCompanion.insert(
          userId: const Value<String?>(userId),
          name: 'Yatırım',
          icon: 'trending_up',
          color: 0xFF00897B,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final Category? row = await db.categoryDao.getById(id);
      expect(row, isNotNull);
      expect(row!.isCustom, isTrue);
      expect(row.syncStatus, SyncStatus.pendingCreate);
      expect(row.userId, userId);
    });

    test('updateCategory should bump syncStatus to pending_update', () async {
      final List<Category> defaults = await db.categoryDao.getDefaults();
      final Category market = defaults.first;
      // Sanity — seeded rows start as synced.
      expect(market.syncStatus, SyncStatus.synced);

      await db.categoryDao.updateCategory(
        market.id,
        const CategoriesCompanion(name: Value<String>('Market & Bakkal')),
      );

      final Category? updated = await db.categoryDao.getById(market.id);
      expect(updated!.name, 'Market & Bakkal');
      expect(updated.syncStatus, SyncStatus.pendingUpdate);
    });

    test('getPendingSync should return only pending rows', () async {
      await db.categoryDao.insertCustom(
        CategoriesCompanion.insert(
          userId: const Value<String?>('u1'),
          name: 'Tasarruf',
          icon: 'savings',
          color: 0xFF558B2F,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final List<Category> pending = await db.categoryDao.getPendingSync();
      expect(pending, hasLength(1));
      expect(pending.first.syncStatus, SyncStatus.pendingCreate);
    });
  });
}
