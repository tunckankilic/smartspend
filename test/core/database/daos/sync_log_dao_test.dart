import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  group('SyncLogDao', () {
    test('log should persist a row with UTC timestamp', () async {
      await db.syncLogDao.log(
        tableName: 'receipts',
        recordId: 'rec-1',
        operation: SyncOperation.create,
        success: true,
        userId: 'u-1',
      );
      final List<SyncLogData> rows = await db.syncLogDao.recent();
      expect(rows, hasLength(1));
      expect(rows.single.logTableName, 'receipts');
      expect(rows.single.success, isTrue);
      expect(rows.single.attemptedAt.isUtc, isTrue);
    });

    test('failures should return only success=false rows', () async {
      await db.syncLogDao.log(
        tableName: 'expenses',
        recordId: 'e-1',
        operation: SyncOperation.create,
        success: true,
      );
      await db.syncLogDao.log(
        tableName: 'expenses',
        recordId: 'e-2',
        operation: SyncOperation.update,
        success: false,
        errorMessage: 'connection reset',
      );
      final List<SyncLogData> failures = await db.syncLogDao.failures();
      expect(failures, hasLength(1));
      expect(failures.single.recordId, 'e-2');
      expect(failures.single.errorMessage, 'connection reset');
    });

    test('clear should empty the log', () async {
      await db.syncLogDao.log(
        tableName: 'receipts',
        recordId: 'r-1',
        operation: SyncOperation.delete,
        success: true,
      );
      expect(await db.syncLogDao.recent(), isNotEmpty);
      await db.syncLogDao.clear();
      expect(await db.syncLogDao.recent(), isEmpty);
    });
  });
}
