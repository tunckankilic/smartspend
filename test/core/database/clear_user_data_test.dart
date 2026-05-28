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
