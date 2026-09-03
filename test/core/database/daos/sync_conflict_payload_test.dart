import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';

import '../../../helpers/test_database.dart';

/// The 1.3.0 promise: last-write-wins may still pick a winner, but the loser
/// is no longer thrown away.
///
/// Before this, every `apply*FromRemote` returned `false` on the "local is
/// newer" path and the remote row simply ceased to exist — `sync_log` kept a
/// note that *a* conflict had happened, with none of the data. For a single
/// user with two devices that is silent data loss, which is why these tests
/// check all seven tables rather than a representative one: a table that
/// forgets to quarantine is exactly as lossy as the old behaviour, and it
/// would be invisible.
void main() {
  late AppDatabase db;
  late int categoryId;

  setUp(() async {
    db = createTestDatabase();
    categoryId = (await db.categoryDao.getDefaults()).first.id;
  });
  tearDown(() async => db.close());

  final DateTime older = DateTime.utc(2026, 5, 1, 12);
  final DateTime newer = DateTime.utc(2026, 6, 1, 12);

  Future<SyncConflictPayload> singleQuarantined() async {
    final List<SyncConflictPayload> rows =
        await db.syncDao.getConflictPayloads();
    expect(rows, hasLength(1));
    return rows.single;
  }

  group('SyncDao conflict quarantine — every syncable table', () {
    test('categories', () async {
      Future<bool> apply(DateTime at) => db.syncDao.applyCategoryFromRemote(
            remoteId: 'cat-1',
            remotePayload: <String, dynamic>{'id': 'cat-1', 'name': 'Remote'},
            name: at == newer ? 'Local wins' : 'Remote loses',
            icon: 'flight',
            color: 1,
            isCustom: true,
            sortOrder: 9,
            updatedAt: at,
            userId: 'user-1',
          );

      expect(await apply(newer), isTrue);
      expect(await apply(older), isFalse);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.conflictTableName, 'categories');
      expect(row.remoteId, 'cat-1');
      expect(row.userId, 'user-1');
      // The local row is untouched: the winner still won.
      expect(
        (await db.syncDao.findCategoryByRemoteId('cat-1'))!.name,
        'Local wins',
      );
    });

    test('receipts', () async {
      Future<bool> apply(DateTime at) => db.syncDao.applyReceiptFromRemote(
            remoteId: 'rcpt-1',
            remotePayload: <String, dynamic>{'id': 'rcpt-1', 'total': 999},
            date: older,
            total: at == newer ? 5000 : 999,
            currency: 'TRY',
            createdAt: older,
            updatedAt: at,
            userId: 'user-1',
          );

      expect(await apply(newer), isTrue);
      expect(await apply(older), isFalse);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.conflictTableName, 'receipts');
      expect(row.remoteId, 'rcpt-1');
      expect((await db.syncDao.findReceiptByRemoteId('rcpt-1'))!.total, 5000);
    });

    test('expenses', () async {
      Future<bool> apply(DateTime at) => db.syncDao.applyExpenseFromRemote(
            remoteId: 'exp-1',
            remotePayload: <String, dynamic>{'id': 'exp-1', 'amount': 111},
            amount: at == newer ? 2500 : 111,
            categoryId: categoryId,
            date: older,
            createdAt: older,
            updatedAt: at,
            userId: 'user-1',
          );

      expect(await apply(newer), isTrue);
      expect(await apply(older), isFalse);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.conflictTableName, 'expenses');
      expect(row.remoteId, 'exp-1');
      expect((await db.syncDao.findExpenseByRemoteId('exp-1'))!.amount, 2500);
    });

    test('budgets', () async {
      Future<bool> apply(DateTime at) => db.syncDao.applyBudgetFromRemote(
            remoteId: 'bud-1',
            remotePayload: <String, dynamic>{'id': 'bud-1', 'amount': 1},
            amount: at == newer ? 100000 : 1,
            period: 'monthly',
            startDate: older,
            isActive: true,
            updatedAt: at,
            userId: 'user-1',
            categoryId: categoryId,
          );

      expect(await apply(newer), isTrue);
      expect(await apply(older), isFalse);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.conflictTableName, 'budgets');
      expect(row.remoteId, 'bud-1');
      expect((await db.syncDao.findBudgetByRemoteId('bud-1'))!.amount, 100000);
    });

    test('receipt_items', () async {
      await db.syncDao.applyReceiptFromRemote(
        remoteId: 'rcpt-parent',
        remotePayload: <String, dynamic>{'id': 'rcpt-parent'},
        date: older,
        total: 5000,
        currency: 'TRY',
        createdAt: older,
        updatedAt: older,
      );
      final int receiptId =
          (await db.syncDao.findReceiptByRemoteId('rcpt-parent'))!.id;

      Future<bool> apply(DateTime at) => db.syncDao.applyReceiptItemFromRemote(
            remoteId: 'item-1',
            remotePayload: <String, dynamic>{'id': 'item-1', 'name': 'Bread'},
            receiptId: receiptId,
            name: at == newer ? 'Milk' : 'Bread',
            quantity: 2,
            unitPrice: 500,
            totalPrice: 1000,
            updatedAt: at,
            userId: 'user-1',
          );

      expect(await apply(newer), isTrue);
      expect(await apply(older), isFalse);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.conflictTableName, 'receipt_items');
      expect(row.remoteId, 'item-1');
      expect(
        (await db.syncDao.findReceiptItemByRemoteId('item-1'))!.name,
        'Milk',
      );
    });

    test('tags', () async {
      Future<bool> apply(DateTime at) => db.syncDao.applyTagFromRemote(
            remoteId: 'tag-1',
            remotePayload: <String, dynamic>{'id': 'tag-1', 'name': 'home'},
            name: at == newer ? 'work' : 'home',
            updatedAt: at,
            userId: 'user-1',
          );

      expect(await apply(newer), isTrue);
      expect(await apply(older), isFalse);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.conflictTableName, 'tags');
      expect(row.remoteId, 'tag-1');
      expect((await db.syncDao.findTagByRemoteId('tag-1'))!.name, 'work');
    });

    test('user_corrections', () async {
      Future<bool> apply(DateTime at) =>
          db.syncDao.applyUserCorrectionFromRemote(
            remoteId: 'corr-1',
            remotePayload: <String, dynamic>{'id': 'corr-1', 'count': 1},
            storeName: 'Migros',
            newCategoryId: categoryId,
            count: at == newer ? 9 : 1,
            occurredAt: older,
            updatedAt: at,
            userId: 'user-1',
          );

      expect(await apply(newer), isTrue);
      expect(await apply(older), isFalse);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.conflictTableName, 'user_corrections');
      expect(row.remoteId, 'corr-1');
      expect(
        (await db.syncDao.findUserCorrectionByRemoteId('corr-1'))!.count,
        9,
      );
    });
  });

  group('SyncDao conflict quarantine — what gets stored', () {
    test('keeps the payload verbatim, with foreign keys still remote UUIDs',
        () async {
      // The whole point of storing raw wire JSON: local ids are an artefact
      // of this device and may be renumbered, but the remote UUID is stable,
      // so 1.4.0 can replay the row on any device.
      const Map<String, dynamic> wire = <String, dynamic>{
        'id': 'exp-1',
        'category_id': '0f4b1c2e-remote-uuid',
        'receipt_id': null,
        'amount': 111,
        'note': "Fatih'in kahvesi",
        'is_manual': true,
      };

      Future<bool> apply(DateTime at, int amount) =>
          db.syncDao.applyExpenseFromRemote(
            remoteId: 'exp-1',
            remotePayload: wire,
            amount: amount,
            categoryId: categoryId,
            date: older,
            createdAt: older,
            updatedAt: at,
            userId: 'user-1',
          );

      await apply(newer, 2500);
      await apply(older, 111);

      final SyncConflictPayload row = await singleQuarantined();
      final Map<String, dynamic> decoded =
          jsonDecode(row.remotePayload) as Map<String, dynamic>;
      expect(decoded, wire);
      // Not remapped to `categoryId`, which is a local integer.
      expect(decoded['category_id'], '0f4b1c2e-remote-uuid');
      expect(decoded['receipt_id'], isNull);
      expect(decoded['note'], "Fatih'in kahvesi");
    });

    test('records both sides of the clock so the conflict can be explained',
        () async {
      Future<bool> apply(DateTime at) => db.syncDao.applyTagFromRemote(
            remoteId: 'tag-1',
            remotePayload: <String, dynamic>{'id': 'tag-1'},
            name: 'x',
            updatedAt: at,
          );
      await apply(newer);
      await apply(older);

      final SyncConflictPayload row = await singleQuarantined();
      expect(row.localUpdatedAt.toUtc(), newer);
      expect(row.remoteUpdatedAt.toUtc(), older);
      expect(row.remoteUpdatedAt.isBefore(row.localUpdatedAt), isTrue);
      expect(row.detectedAt.isUtc, isTrue);
    });

    test('quarantines nothing when the remote row legitimately wins',
        () async {
      Future<bool> apply(DateTime at) => db.syncDao.applyTagFromRemote(
            remoteId: 'tag-1',
            remotePayload: <String, dynamic>{'id': 'tag-1'},
            name: 'x',
            updatedAt: at,
          );
      expect(await apply(older), isTrue);
      expect(await apply(newer), isTrue);

      expect(await db.syncDao.getConflictPayloads(), isEmpty);
    });

    test('an equal timestamp counts as a conflict, not a win', () async {
      // `isAfter` is strict, so a remote row with the identical updated_at
      // does not overwrite local. That is a real discard and must be kept.
      Future<bool> apply(DateTime at) => db.syncDao.applyTagFromRemote(
            remoteId: 'tag-1',
            remotePayload: <String, dynamic>{'id': 'tag-1'},
            name: 'x',
            updatedAt: at,
          );
      expect(await apply(older), isTrue);
      expect(await apply(older), isFalse);

      expect(await db.syncDao.getConflictPayloads(), hasLength(1));
    });

    test('every discard is kept, not just the most recent one', () async {
      Future<bool> apply(String remoteId, DateTime at) =>
          db.syncDao.applyTagFromRemote(
            remoteId: remoteId,
            remotePayload: <String, dynamic>{'id': remoteId},
            name: 'x',
            updatedAt: at,
          );
      await apply('tag-1', newer);
      await apply('tag-2', newer);
      await apply('tag-1', older);
      await apply('tag-2', older);
      await apply('tag-1', older);

      expect(await db.syncDao.getConflictPayloads(), hasLength(3));
    });
  });
}
