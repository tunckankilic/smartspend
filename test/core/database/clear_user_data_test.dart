import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  Future<int> categoryCount() async =>
      (await db.select(db.categories).get()).length;

  group('AppDatabase.clearUserData', () {
    test('wipes user expenses but keeps the global seed categories',
        () async {
      final int seededCategories = await categoryCount();
      expect(seededCategories, greaterThan(0));

      final int categoryId =
          (await db.select(db.categories).get()).first.id;

      final DateTime now = DateTime.now().toUtc();
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              userId: const Value<String?>('user-1'),
              amount: 1299,
              categoryId: categoryId,
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect(await db.select(db.expenses).get(), isNotEmpty);

      await db.clearUserData();

      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await categoryCount(), seededCategories);
    });

    test('resets the lastSyncAt watermark so the next sign-in pulls all',
        () async {
      final DateTime now = DateTime.now().toUtc();
      await db.syncDao.setLastSyncAt(now);
      expect((await db.syncDao.getLastSyncAt()) != null, isTrue);

      await db.clearUserData();

      // Without the reset the next session's incremental pull would skip
      // every remote row and leave the dashboard empty.
      expect(await db.syncDao.getLastSyncAt(), null);
    });

    test('preserves non-sync userSettings (theme / locale) on wipe',
        () async {
      await db.into(db.userSettings).insert(
            UserSettingsCompanion.insert(
              key: 'theme_mode',
              value: 'dark',
              updatedAt: DateTime.now().toUtc(),
            ),
          );

      await db.clearUserData();

      final UserSetting? theme = await (db.select(db.userSettings)
            ..where(($UserSettingsTable t) => t.key.equals('theme_mode')))
          .getSingleOrNull();
      expect(theme?.value, 'dark');
    });

    test('removes custom categories while preserving the defaults',
        () async {
      final int seededCategories = await categoryCount();

      final DateTime now = DateTime.now().toUtc();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              userId: const Value<String?>('user-1'),
              name: 'My Custom Category',
              icon: 'star',
              color: 0xFF00FF00,
              isCustom: const Value<bool>(true),
              updatedAt: now,
            ),
          );
      expect(await categoryCount(), seededCategories + 1);

      await db.clearUserData();

      expect(await categoryCount(), seededCategories);
    });
  });
}
