import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late int catA;
  late int catB;

  setUp(() async {
    db = createTestDatabase();
    final List<Category> defaults = await db.categoryDao.getDefaults();
    catA = defaults[0].id;
    catB = defaults[1].id;
  });
  tearDown(() async => db.close());

  final DateTime when = DateTime.utc(2026, 5, 1);

  group('upsertCorrection', () {
    test('should insert a new pending_create row', () async {
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'Migros',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when,
      );
      final UserCorrection? top =
          await db.userCorrectionDao.getTopCorrectionForStore('Migros');
      expect(top, isNotNull);
      expect(top!.count, 1);
      expect(top.syncStatus, SyncStatus.pendingCreate);
    });

    test('should ignore a blank store name', () async {
      await db.userCorrectionDao.upsertCorrection(
        storeName: '   ',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when,
      );
      expect(
        await db.userCorrectionDao.getTopCorrectionForStore('anything'),
        isNull,
      );
    });

    test('should bump count for the same store + category', () async {
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'Migros',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when,
      );
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'MIGROS',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when.add(const Duration(days: 1)),
      );
      final UserCorrection top =
          (await db.userCorrectionDao.getTopCorrectionForStore('migros'))!;
      expect(top.count, 2);
      expect(top.syncStatus, SyncStatus.pendingUpdate);
    });

    test('getTopCorrectionForStore should prefer the highest count', () async {
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'Migros',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when,
      );
      // Two corrections to catB → higher count, should win.
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'Migros',
        oldCategoryId: catA,
        newCategoryId: catB,
        occurredAt: when,
      );
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'Migros',
        oldCategoryId: catA,
        newCategoryId: catB,
        occurredAt: when.add(const Duration(days: 2)),
      );
      final UserCorrection top =
          (await db.userCorrectionDao.getTopCorrectionForStore('Migros'))!;
      expect(top.newCategoryId, catB);
      expect(top.count, 2);
    });

    test('getTopCorrectionForStore should be null for blank input', () async {
      expect(
        await db.userCorrectionDao.getTopCorrectionForStore('   '),
        isNull,
      );
    });
  });

  group('watchAll + getPendingSync', () {
    test('watchAll should emit corrections newest first', () async {
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'A',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when,
      );
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'B',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when.add(const Duration(days: 1)),
      );
      final List<UserCorrection> rows =
          await db.userCorrectionDao.watchAll().first;
      expect(rows, hasLength(2));
      expect(rows.first.storeName, 'B');
    });

    test('getPendingSync should return rows awaiting push', () async {
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'A',
        oldCategoryId: null,
        newCategoryId: catA,
        occurredAt: when,
      );
      final List<UserCorrection> pending =
          await db.userCorrectionDao.getPendingSync();
      expect(pending, hasLength(1));
    });
  });
}
