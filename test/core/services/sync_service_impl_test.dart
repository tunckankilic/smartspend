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
