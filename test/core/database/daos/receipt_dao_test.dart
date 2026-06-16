import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

ReceiptsCompanion _sampleReceipt({
  String storeName = 'BİM',
  int total = 12345,
  DateTime? date,
}) {
  return ReceiptsCompanion.insert(
    storeName: Value<String?>(storeName),
    date: date ?? DateTime.utc(2026, 5, 20),
    total: total,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  group('ReceiptDao', () {
    test('insertReceipt should stamp pending_create and timestamps', () async {
      final int id = await db.receiptDao.insertReceipt(_sampleReceipt());

      final Receipt? row = await db.receiptDao.getById(id);
      expect(row, isNotNull);
      expect(row!.storeName, 'BİM');
      expect(row.total, 12345);
      expect(row.syncStatus, SyncStatus.pendingCreate);
      expect(row.createdAt.isUtc, isTrue);
    });

    test('updateReceipt should flip status to pending_update', () async {
      final int id = await db.receiptDao.insertReceipt(_sampleReceipt());
      await db.receiptDao.updateReceipt(
        id,
        const ReceiptsCompanion(total: Value<int>(99999)),
      );

      final Receipt? row = await db.receiptDao.getById(id);
      expect(row!.total, 99999);
      expect(row.syncStatus, SyncStatus.pendingUpdate);
    });

    test('softDeleteReceipt should mark pending_delete without removing row',
        () async {
      final int id = await db.receiptDao.insertReceipt(_sampleReceipt());
      await db.receiptDao.softDeleteReceipt(id);

      final Receipt? row = await db.receiptDao.getById(id);
      expect(row, isNotNull);
      expect(row!.syncStatus, SyncStatus.pendingDelete);

      final List<Receipt> visible = await db.receiptDao.getAll();
      expect(visible, isEmpty,
          reason: 'soft-deleted rows must not appear in getAll');
    });

    test('searchByStore should match case-insensitively', () async {
      await db.receiptDao
          .insertReceipt(_sampleReceipt(storeName: 'Migros'));
      await db.receiptDao
          .insertReceipt(_sampleReceipt(storeName: 'A101'));

      final List<Receipt> hits = await db.receiptDao.searchByStore('migros');
      expect(hits, hasLength(1));
      expect(hits.first.storeName, 'Migros');
    });
  });
}
