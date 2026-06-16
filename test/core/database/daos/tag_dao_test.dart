import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() => db.close());

  group('findOrCreate', () {
    test('should insert a new tag with pending_create status', () async {
      final int id = await db.tagDao.findOrCreate('Kahve');
      final Tag? row = await db.tagDao.findByName('Kahve');
      expect(row, isNotNull);
      expect(row!.id, id);
      expect(row.syncStatus, SyncStatus.pendingCreate);
    });

    test('should dedupe case-insensitively', () async {
      final int a = await db.tagDao.findOrCreate('Kahve');
      final int b = await db.tagDao.findOrCreate('kahve');
      final int c = await db.tagDao.findOrCreate('  KAHVE ');
      expect(a, b);
      expect(a, c);
      expect((await db.tagDao.getAll()).length, 1);
    });

    test('should reject empty / whitespace input', () async {
      expect(
        () => db.tagDao.findOrCreate('   '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('attach + read', () {
    test('setTagsForExpense should replace the tag set', () async {
      final int t1 = await db.tagDao.findOrCreate('kahve');
      final int t2 = await db.tagDao.findOrCreate('iş');
      final int t3 = await db.tagDao.findOrCreate('hediye');

      await db.tagDao.setTagsForExpense(42, <int>{t1, t2});
      final List<Tag> first = await db.tagDao.getForExpense(42);
      expect(first.map((Tag t) => t.id).toSet(), <int>{t1, t2});

      await db.tagDao.setTagsForExpense(42, <int>{t2, t3});
      final List<Tag> second = await db.tagDao.getForExpense(42);
      expect(second.map((Tag t) => t.id).toSet(), <int>{t2, t3});
    });

    test('resolveAndAttach should idempotently sync names → links',
        () async {
      final Set<int> first = await db.tagDao.resolveAndAttach(
        7,
        <String>['kahve', 'iş', '  hediye  '],
      );
      expect(first.length, 3);
      expect((await db.tagDao.getForExpense(7)).length, 3);

      final Set<int> second = await db.tagDao.resolveAndAttach(
        7,
        <String>['kahve'],
      );
      expect(second.length, 1);
      expect((await db.tagDao.getForExpense(7)).length, 1);
    });

    test('getTagsForExpenseIds should batch-load tags', () async {
      final int a = await db.tagDao.findOrCreate('kahve');
      final int b = await db.tagDao.findOrCreate('iş');
      await db.tagDao.setTagsForExpense(1, <int>{a});
      await db.tagDao.setTagsForExpense(2, <int>{a, b});

      final Map<int, List<String>> batched =
          await db.tagDao.getTagsForExpenseIds(<int>[1, 2, 3]);
      expect(batched[1], <String>['kahve']);
      expect(batched[2], <String>['iş', 'kahve']);
      expect(batched.containsKey(3), isFalse);
    });

    test('getTagsForExpenseIds should return empty for empty input',
        () async {
      expect(
        await db.tagDao.getTagsForExpenseIds(const <int>[]),
        isEmpty,
      );
    });
  });
}
