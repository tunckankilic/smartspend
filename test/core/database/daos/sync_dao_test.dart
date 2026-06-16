import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late int categoryId;

  setUp(() async {
    db = createTestDatabase();
    final List<Category> defaults = await db.categoryDao.getDefaults();
    categoryId = defaults.first.id;
  });
  tearDown(() async => db.close());

  final DateTime base = DateTime.utc(2026, 5, 1, 12);

  group('SyncDao watermark', () {
    test('getLastSyncAt should be null on a fresh database', () async {
      expect(await db.syncDao.getLastSyncAt(), isNull);
    });

    test('setLastSyncAt should round-trip a UTC timestamp', () async {
      await db.syncDao.setLastSyncAt(base);
      final DateTime? got = await db.syncDao.getLastSyncAt();
      expect(got, isNotNull);
      expect(got!.toUtc(), base);
    });

    test('setLastSyncAt should overwrite the previous watermark', () async {
      await db.syncDao.setLastSyncAt(base);
      final DateTime later = base.add(const Duration(days: 1));
      await db.syncDao.setLastSyncAt(later);
      expect((await db.syncDao.getLastSyncAt())!.toUtc(), later);
    });
  });

  group('SyncDao applyCategoryFromRemote', () {
    Future<bool> apply({
      String remoteId = 'cat-remote',
      String name = 'Travel',
      DateTime? updatedAt,
    }) {
      return db.syncDao.applyCategoryFromRemote(
        remoteId: remoteId,
        name: name,
        icon: 'flight',
        color: 1,
        isCustom: true,
        sortOrder: 99,
        updatedAt: updatedAt ?? base,
        userId: 'user-1',
      );
    }

    test('should insert when the remoteId is unknown', () async {
      expect(await apply(), isTrue);
      final Category? row =
          await db.syncDao.findCategoryByRemoteId('cat-remote');
      expect(row, isNotNull);
      expect(row!.name, 'Travel');
      expect(row.syncStatus, SyncStatus.synced);
    });

    test('should skip when incoming row is not newer (last-write-wins)',
        () async {
      await apply();
      final bool wrote = await apply(name: 'Stale', updatedAt: base);
      expect(wrote, isFalse);
      final Category? row =
          await db.syncDao.findCategoryByRemoteId('cat-remote');
      expect(row!.name, 'Travel');
    });

    test('should update when incoming row is newer', () async {
      await apply();
      final bool wrote = await apply(
        name: 'Newer',
        updatedAt: base.add(const Duration(hours: 1)),
      );
      expect(wrote, isTrue);
      final Category? row =
          await db.syncDao.findCategoryByRemoteId('cat-remote');
      expect(row!.name, 'Newer');
    });

    test('localCategoryIdForRemote should resolve id and tolerate null',
        () async {
      await apply();
      final Category? row =
          await db.syncDao.findCategoryByRemoteId('cat-remote');
      expect(await db.syncDao.localCategoryIdForRemote('cat-remote'), row!.id);
      expect(await db.syncDao.localCategoryIdForRemote(null), isNull);
      expect(await db.syncDao.categoryRemoteId(row.id), 'cat-remote');
    });

    test('markCategorySynced should stamp remoteId and synced status',
        () async {
      await apply();
      final Category row =
          (await db.syncDao.findCategoryByRemoteId('cat-remote'))!;
      await db.syncDao.markCategorySynced(row.id, remoteId: 'cat-new');
      final Category? updated =
          await db.syncDao.findCategoryByRemoteId('cat-new');
      expect(updated, isNotNull);
      expect(updated!.syncStatus, SyncStatus.synced);
    });
  });

  group('SyncDao applyReceiptFromRemote', () {
    Future<bool> apply({DateTime? updatedAt, int total = 5000}) {
      return db.syncDao.applyReceiptFromRemote(
        remoteId: 'rcpt-remote',
        date: base,
        total: total,
        currency: 'TRY',
        createdAt: base,
        updatedAt: updatedAt ?? base,
        userId: 'user-1',
        storeName: 'Migros',
      );
    }

    test('should insert, update on newer, and skip on stale', () async {
      expect(await apply(), isTrue);
      expect(await apply(total: 1, updatedAt: base), isFalse);
      expect(
        await apply(total: 9999, updatedAt: base.add(const Duration(hours: 1))),
        isTrue,
      );
      final Receipt? row =
          await db.syncDao.findReceiptByRemoteId('rcpt-remote');
      expect(row!.total, 9999);
    });

    test('receiptRemoteId / localReceiptIdForRemote should resolve', () async {
      await apply();
      final Receipt row =
          (await db.syncDao.findReceiptByRemoteId('rcpt-remote'))!;
      expect(await db.syncDao.receiptRemoteId(row.id), 'rcpt-remote');
      expect(
        await db.syncDao.localReceiptIdForRemote('rcpt-remote'),
        row.id,
      );
      expect(await db.syncDao.localReceiptIdForRemote(null), isNull);
    });

    test('hardDeleteReceipt should remove the row', () async {
      await apply();
      final Receipt row =
          (await db.syncDao.findReceiptByRemoteId('rcpt-remote'))!;
      await db.syncDao.hardDeleteReceipt(row.id);
      expect(await db.syncDao.findReceiptByRemoteId('rcpt-remote'), isNull);
    });

    test('markReceiptSynced should keep the row synced', () async {
      await apply();
      final Receipt row =
          (await db.syncDao.findReceiptByRemoteId('rcpt-remote'))!;
      await db.syncDao.markReceiptSynced(row.id);
      final Receipt? after =
          await db.syncDao.findReceiptByRemoteId('rcpt-remote');
      expect(after!.syncStatus, SyncStatus.synced);
    });
  });

  group('SyncDao applyExpenseFromRemote', () {
    Future<bool> apply({DateTime? updatedAt, int amount = 2500}) {
      return db.syncDao.applyExpenseFromRemote(
        remoteId: 'exp-remote',
        amount: amount,
        categoryId: categoryId,
        date: base,
        createdAt: base,
        updatedAt: updatedAt ?? base,
        userId: 'user-1',
        note: 'lunch',
      );
    }

    test('should insert, update on newer, skip on stale', () async {
      expect(await apply(), isTrue);
      expect(await apply(amount: 1, updatedAt: base), isFalse);
      expect(
        await apply(amount: 7777, updatedAt: base.add(const Duration(days: 1))),
        isTrue,
      );
      final Expense row =
          (await db.syncDao.findExpenseByRemoteId('exp-remote'))!;
      expect(row.amount, 7777);
    });

    test('markExpenseSynced + hardDeleteExpense', () async {
      await apply();
      final Expense row =
          (await db.syncDao.findExpenseByRemoteId('exp-remote'))!;
      await db.syncDao.markExpenseSynced(row.id, remoteId: 'exp-remote');
      await db.syncDao.hardDeleteExpense(row.id);
      expect(await db.syncDao.findExpenseByRemoteId('exp-remote'), isNull);
    });
  });

  group('SyncDao applyBudgetFromRemote', () {
    Future<bool> apply({DateTime? updatedAt, int amount = 100000}) {
      return db.syncDao.applyBudgetFromRemote(
        remoteId: 'bud-remote',
        amount: amount,
        period: 'monthly',
        startDate: base,
        isActive: true,
        updatedAt: updatedAt ?? base,
        userId: 'user-1',
        categoryId: categoryId,
      );
    }

    test('should insert, update on newer, skip on stale', () async {
      expect(await apply(), isTrue);
      expect(await apply(amount: 1, updatedAt: base), isFalse);
      expect(
        await apply(
          amount: 200000,
          updatedAt: base.add(const Duration(days: 1)),
        ),
        isTrue,
      );
      final Budget row = (await db.syncDao.findBudgetByRemoteId('bud-remote'))!;
      expect(row.amount, 200000);
    });

    test('markBudgetSynced + hardDeleteBudget', () async {
      await apply();
      final Budget row = (await db.syncDao.findBudgetByRemoteId('bud-remote'))!;
      await db.syncDao.markBudgetSynced(row.id, remoteId: 'bud-remote');
      await db.syncDao.hardDeleteBudget(row.id);
      expect(await db.syncDao.findBudgetByRemoteId('bud-remote'), isNull);
    });
  });

  group('SyncDao receipt items and tags', () {
    test('applyReceiptItemFromRemote should insert and update', () async {
      await db.syncDao.applyReceiptFromRemote(
        remoteId: 'rcpt-x',
        date: base,
        total: 5000,
        currency: 'TRY',
        createdAt: base,
        updatedAt: base,
      );
      final int receiptId =
          (await db.syncDao.findReceiptByRemoteId('rcpt-x'))!.id;

      Future<bool> apply({DateTime? updatedAt, int totalPrice = 1000}) {
        return db.syncDao.applyReceiptItemFromRemote(
          remoteId: 'item-1',
          receiptId: receiptId,
          name: 'Milk',
          quantity: 2,
          unitPrice: 500,
          totalPrice: totalPrice,
          updatedAt: updatedAt ?? base,
        );
      }

      expect(await apply(), isTrue);
      expect(await apply(updatedAt: base), isFalse);
      expect(
        await apply(
          totalPrice: 3000,
          updatedAt: base.add(const Duration(hours: 2)),
        ),
        isTrue,
      );
      final ReceiptItem item =
          (await db.syncDao.findReceiptItemByRemoteId('item-1'))!;
      expect(item.totalPrice, 3000);
      await db.syncDao.markReceiptItemSynced(item.id, remoteId: 'item-1');
    });

    test('getPendingReceiptItems should return only pending rows', () async {
      await db.syncDao.applyReceiptFromRemote(
        remoteId: 'rcpt-y',
        date: base,
        total: 100,
        currency: 'TRY',
        createdAt: base,
        updatedAt: base,
      );
      final int receiptId =
          (await db.syncDao.findReceiptByRemoteId('rcpt-y'))!.id;
      await db.into(db.receiptItems).insert(
            ReceiptItemsCompanion.insert(
              receiptId: receiptId,
              name: 'Pending item',
              unitPrice: 100,
              totalPrice: 100,
              updatedAt: base,
              syncStatus: const Value<String>(SyncStatus.pendingCreate),
            ),
          );
      final List<ReceiptItem> pending =
          await db.syncDao.getPendingReceiptItems();
      expect(pending, hasLength(1));
      expect(pending.first.name, 'Pending item');
    });

    test('applyTagFromRemote + getPendingTags', () async {
      expect(
        await db.syncDao.applyTagFromRemote(
          remoteId: 'tag-1',
          name: 'work',
          updatedAt: base,
        ),
        isTrue,
      );
      final Tag tag = (await db.syncDao.findTagByRemoteId('tag-1'))!;
      await db.syncDao.markTagSynced(tag.id, remoteId: 'tag-1');

      await db.into(db.tags).insert(
            TagsCompanion.insert(
              name: 'pending-tag',
              updatedAt: base,
              syncStatus: const Value<String>(SyncStatus.pendingUpdate),
            ),
          );
      final List<Tag> pending = await db.syncDao.getPendingTags();
      expect(pending.map((Tag t) => t.name), contains('pending-tag'));
    });
  });

  group('SyncDao applyUserCorrectionFromRemote', () {
    test('should insert, update on newer, skip on stale', () async {
      Future<bool> apply({DateTime? updatedAt, int count = 1}) {
        return db.syncDao.applyUserCorrectionFromRemote(
          remoteId: 'corr-1',
          storeName: 'Migros',
          newCategoryId: categoryId,
          count: count,
          occurredAt: base,
          updatedAt: updatedAt ?? base,
          userId: 'user-1',
        );
      }

      expect(await apply(), isTrue);
      expect(await apply(count: 9, updatedAt: base), isFalse);
      expect(
        await apply(count: 5, updatedAt: base.add(const Duration(hours: 1))),
        isTrue,
      );
      final UserCorrection row =
          (await db.syncDao.findUserCorrectionByRemoteId('corr-1'))!;
      expect(row.count, 5);
      await db.syncDao.markUserCorrectionSynced(row.id, remoteId: 'corr-1');
    });
  });
}
