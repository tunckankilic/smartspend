import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/sync_remote_data_source.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/services/sync_service_impl.dart';

import '../../helpers/test_database.dart';

class _MockRemote extends Mock implements SyncRemoteDataSource {}

class _MockConnectivity extends Mock implements Connectivity {}

void main() {
  late AppDatabase db;
  late _MockRemote remote;
  late _MockConnectivity connectivity;
  late SupabaseSyncServiceImpl service;

  setUp(() async {
    db = createTestDatabase();
    await db.categoryDao.getAll(); // Force onCreate seeding.
    remote = _MockRemote();
    connectivity = _MockConnectivity();
    service = SupabaseSyncServiceImpl(
      database: db,
      remote: remote,
      connectivity: connectivity,
    );
    // Default: nothing to pull.
    when(() => remote.fetchSince(any(), any()))
        .thenAnswer((_) async => <Map<String, dynamic>>[]);
  });

  tearDown(() async {
    await service.dispose();
    await db.close();
  });

  Future<int> insertPendingCategory() {
    return db.categoryDao.insertCustom(
      CategoriesCompanion.insert(
        name: 'Hobi',
        icon: 'star',
        color: 0xFF00FF00,
        sortOrder: const Value<int>(99),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  group('push', () {
    test('should upsert a pending category and mark it synced', () async {
      await insertPendingCategory();
      when(() => remote.upsert('categories', any()))
          .thenAnswer((_) async => 'cat-remote-1');

      final Either<Failure, SyncReport> result = await service.push();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pushed, 1);
      expect(report.failed, 0);
      verify(() => remote.upsert('categories', any())).called(1);
      expect(await db.categoryDao.getPendingSync(), isEmpty);
    });

    test('should isolate a row failure and leave the row pending', () async {
      await insertPendingCategory();
      when(() => remote.upsert('categories', any()))
          .thenThrow(Exception('boom'));

      final Either<Failure, SyncReport> result = await service.push();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pushed, 0);
      expect(report.failed, 1);
      expect(await db.categoryDao.getPendingSync(), hasLength(1));
      expect(await db.syncLogDao.failures(), isNotEmpty);
    });
  });

  group('pull', () {
    test('should fold a remote category into Drift', () async {
      when(() => remote.fetchSince('categories', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cat-remote-9',
            'name': 'Seyahat',
            'icon': 'flight',
            'color': 0xFF112233,
            'is_custom': true,
            'sort_order': 50,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'user_id': 'user-1',
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pulled, 1);
      final List<Category> all = await db.categoryDao.getAll();
      expect(all.any((Category c) => c.name == 'Seyahat'), isTrue);
    });

    test('should advance the last-sync watermark', () async {
      expect(await db.syncDao.getLastSyncAt(), isNull);

      await service.pull();

      expect(await db.syncDao.getLastSyncAt(), isNotNull);
    });
  });

  group('pull missing tables', () {
    String nowIso() => DateTime.now().toUtc().toIso8601String();

    test('should fold a remote tag into Drift', () async {
      when(() => remote.fetchSince('tags', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'tag-remote-1',
            'name': 'work',
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pulled, 1);
      expect(await db.syncDao.findTagByRemoteId('tag-remote-1'), isNotNull);
    });

    test('should fold a receipt item once its parent receipt is present',
        () async {
      when(() => remote.fetchSince('receipts', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'rcpt-remote-1',
            'store_name': 'Migros',
            'date': '2026-05-01',
            'total': 1299,
            'currency': 'TRY',
            'image_path': null,
            'storage_object_path': null,
            'raw_ocr_text': null,
            'confidence_score': null,
            'warranty_end_date': null,
            'created_at': nowIso(),
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );
      when(() => remote.fetchSince('receipt_items', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'item-remote-1',
            'receipt_id': 'rcpt-remote-1',
            'name': 'Süt',
            'quantity': 2,
            'unit_price': 1500,
            'total_price': 3000,
            'category_id': null,
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      // Receipt + item.
      expect(report.pulled, 2);
      expect(
        await db.syncDao.findReceiptItemByRemoteId('item-remote-1'),
        isNotNull,
      );
    });

    test('should skip a receipt item whose parent receipt is missing',
        () async {
      when(() => remote.fetchSince('receipt_items', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'item-remote-2',
            'receipt_id': 'rcpt-does-not-exist',
            'name': 'Ekmek',
            'quantity': 1,
            'unit_price': 500,
            'total_price': 500,
            'category_id': null,
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pulled, 0);
      expect(
        await db.syncDao.findReceiptItemByRemoteId('item-remote-2'),
        isNull,
      );
    });

    test('should fold a user correction once its category is present',
        () async {
      when(() => remote.fetchSince('categories', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cat-remote-9',
            'name': 'Seyahat',
            'icon': 'flight',
            'color': 0xFF112233,
            'is_custom': true,
            'sort_order': 50,
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );
      when(() => remote.fetchSince('user_corrections', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'uc-remote-1',
            'store_name': 'THY',
            'old_category_id': null,
            'new_category_id': 'cat-remote-9',
            'count': 3,
            'occurred_at': nowIso(),
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      // Category + correction.
      expect(report.pulled, 2);
      expect(
        await db.syncDao.findUserCorrectionByRemoteId('uc-remote-1'),
        isNotNull,
      );
    });
  });

  group('sync', () {
    test('should merge push and pull reports', () async {
      await insertPendingCategory();
      when(() => remote.upsert('categories', any()))
          .thenAnswer((_) async => 'cat-remote-1');
      when(() => remote.fetchSince('categories', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cat-remote-9',
            'name': 'Seyahat',
            'icon': 'flight',
            'color': 0xFF112233,
            'is_custom': true,
            'sort_order': 50,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'user_id': 'user-1',
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.sync();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pushed, 1);
      expect(report.pulled, 1);
    });

    test('should report a pending phase after a failed-row sync', () async {
      await insertPendingCategory();
      when(() => remote.upsert('categories', any()))
          .thenThrow(Exception('offline'));

      await service.sync();

      final SyncPhase phase = await service.watchStatus().first;
      expect(phase, isA<SyncPhasePending>());
      expect((phase as SyncPhasePending).count, 1);
    });
  });
}
