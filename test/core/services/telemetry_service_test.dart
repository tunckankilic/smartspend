import 'dart:async';
import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/services/telemetry_remote_data_source.dart';
import 'package:smartspend/core/services/telemetry_service.dart';
import 'package:smartspend/core/services/telemetry_service_impl.dart';

import '../../helpers/test_database.dart';

/// Captures what would go over the wire.
class _FakeRemote implements TelemetryRemoteDataSource {
  String? userId = 'user-1';
  bool shouldThrow = false;

  /// Every batch handed to [upsertCounters], flattened.
  final List<Map<String, dynamic>> uploaded = <Map<String, dynamic>>[];
  int calls = 0;

  @override
  String? get currentUserId => userId;

  @override
  Future<void> upsertCounters(List<Map<String, dynamic>> rows) async {
    calls++;
    if (shouldThrow) throw StateError('network down');
    uploaded.addAll(rows);
  }
}

/// Sync engine stand-in whose phase stream the test drives by hand.
class _FakeSyncService implements SyncService {
  final StreamController<SyncPhase> controller =
      StreamController<SyncPhase>.broadcast();

  void emit(SyncPhase phase) => controller.add(phase);

  @override
  Stream<SyncPhase> watchStatus() => controller.stream;

  @override
  Future<void> dispose() async => controller.close();

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<Either<Failure, SyncReport>> pull() async =>
      const Right<Failure, SyncReport>(SyncReport());

  @override
  Future<Either<Failure, SyncReport>> push() async =>
      const Right<Failure, SyncReport>(SyncReport());

  @override
  Future<Either<Failure, SyncReport>> sync() async =>
      const Right<Failure, SyncReport>(SyncReport());

  @override
  void start() {}
}

void main() {
  late AppDatabase db;
  late _FakeRemote remote;
  late _FakeSyncService sync;
  late DateTime now;
  late TelemetryServiceImpl service;

  TelemetryServiceImpl build() => TelemetryServiceImpl(
        database: db,
        remote: remote,
        syncService: sync,
        clock: () => now,
        // Seeded so the generated install id is reproducible in assertions.
        random: Random(7),
      );

  setUp(() {
    db = createTestDatabase();
    remote = _FakeRemote();
    sync = _FakeSyncService();
    now = DateTime.utc(2026, 9, 1, 10, 30);
    service = build();
  });

  tearDown(() async {
    await service.dispose();
    await sync.dispose();
    await db.close();
  });

  group('record', () {
    test('should bucket the counter by UTC day', () async {
      await service.record(ProductEvent.scanStarted);

      final ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(row.count, 1);
    });

    test('should carry the dimension when the event has one', () async {
      await service.record(
        ProductEvent.taxProfileCompleted,
        dimension: TelemetryDimension.limited,
      );

      final ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'tax_profile_completed',
        dimension: 'limited',
        day: '2026-09-01',
      ))!;
      expect(row.count, 1);
    });

    test('should roll over at UTC midnight, not local midnight', () async {
      now = DateTime.utc(2026, 9, 1, 23, 59);
      await service.record(ProductEvent.scanStarted);
      now = DateTime.utc(2026, 9, 2, 0, 1);
      await service.record(ProductEvent.scanStarted);

      expect(await db.productEventDao.getAll(), hasLength(2));
    });

    // Opting out has to stop collection at the source. If it only stopped the
    // upload, an opted-out device would still be accumulating a backlog that
    // one bug or one toggle away would ship.
    test('should collect nothing at all when the user has opted out',
        () async {
      await service.setEnabled(enabled: false);

      await service.record(ProductEvent.scanStarted);

      expect(await db.productEventDao.getAll(), isEmpty);
    });

    test('should never throw, even with the database closed', () async {
      await db.close();

      await expectLater(service.record(ProductEvent.scanStarted), completes);
    });
  });

  group('flush', () {
    test('should upload the absolute count and stamp the row synced',
        () async {
      await service.record(ProductEvent.scanStarted);
      await service.record(ProductEvent.scanStarted);

      expect(await service.flush(), 1);

      expect(remote.uploaded.single['event_key'], 'scan_started');
      expect(remote.uploaded.single['count'], 2);
      expect(remote.uploaded.single['day'], '2026-09-01');
      expect(remote.uploaded.single['user_id'], 'user-1');
      expect(remote.uploaded.single['company_id'], isNull);
      expect(await db.productEventDao.getPendingSync(), isEmpty);
    });

    // The property the whole D-14 design buys: a retry after a request that
    // actually succeeded but whose response was lost writes the same absolute
    // value again. With server-side addition it would have double-counted.
    test('should be idempotent — a replay sends the same value', () async {
      await service.record(ProductEvent.scanStarted);
      remote.shouldThrow = true;
      expect(await service.flush(), 0);

      remote.shouldThrow = false;
      expect(await service.flush(), 1);

      expect(remote.calls, 2);
      expect(remote.uploaded.single['count'], 1);
    });

    test('should leave the batch pending when the upload fails', () async {
      await service.record(ProductEvent.scanStarted);
      remote.shouldThrow = true;

      expect(await service.flush(), 0);

      expect(await db.productEventDao.getPendingSync(), hasLength(1));
    });

    test('should do nothing without a session', () async {
      await service.record(ProductEvent.scanStarted);
      remote.userId = null;

      expect(await service.flush(), 0);
      expect(remote.calls, 0);
      expect(await db.productEventDao.getPendingSync(), hasLength(1));
    });

    test('should do nothing when the user has opted out', () async {
      await service.record(ProductEvent.scanStarted);
      await service.setEnabled(enabled: false);

      expect(await service.flush(), 0);
      expect(remote.calls, 0);
    });

    test('should prune uploaded counters past the retention window', () async {
      now = DateTime.utc(2026, 8, 1);
      await service.record(ProductEvent.scanStarted);
      await service.flush();

      now = DateTime.utc(2026, 9, 1);
      await service.record(ProductEvent.scanApproved);
      await service.flush();

      final List<String> days = (await db.productEventDao.getAll())
          .map((ProductEventCounter c) => c.day)
          .toList();
      expect(days, <String>['2026-09-01']);
    });

    test('should keep an uploaded counter inside the retention window',
        () async {
      await service.record(ProductEvent.scanStarted);
      await service.flush();

      now = now.add(const Duration(days: 2));
      await service.flush();

      expect(await db.productEventDao.getAll(), hasLength(1));
    });
  });

  group('payload discipline (KVKK)', () {
    // The sert kural of Block 3, asserted rather than trusted. If someone ever
    // adds a field to the upload map, this test fails and they have to justify
    // it — which is exactly the conversation that should happen.
    test('should send only the whitelisted keys and nothing else', () async {
      await service.record(
        ProductEvent.taxProfileCompleted,
        dimension: TelemetryDimension.serbestMeslek,
      );
      await service.flush();

      expect(
        remote.uploaded.single.keys.toSet(),
        <String>{
          'user_id',
          'company_id',
          'device_id',
          'event_key',
          'dimension',
          'day',
          'count',
        },
      );
    });

    test('should send no free text, no amount and no document content',
        () async {
      // Two receipts' worth of activity, the shape a real session produces.
      await service.record(ProductEvent.scanStarted);
      await service.record(ProductEvent.scanApproved);
      await service.record(
        ProductEvent.taxProfileCompleted,
        dimension: TelemetryDimension.limited,
      );
      await service.flush();

      for (final Map<String, dynamic> row in remote.uploaded) {
        for (final MapEntry<String, dynamic> entry in row.entries) {
          final Object? value = entry.value;
          if (value == null || value is int) continue;
          expect(
            value,
            isA<String>(),
            reason: '${entry.key} is neither a counter nor an identifier',
          );
          // Every string on the wire is an identifier: lowercase, no spaces,
          // no punctuation beyond `_` and `-`. A store name, an OCR line or
          // "1.249,90 TL" cannot survive this shape.
          expect(
            RegExp(r'^[a-z0-9_-]*$').hasMatch(value as String),
            isTrue,
            reason: '${entry.key} = "$value" is not an identifier',
          );
        }
      }
    });

    test('the generated device id matches the shape the server enforces',
        () async {
      await service.record(ProductEvent.scanStarted);
      await service.flush();

      final String deviceId = remote.uploaded.single['device_id'] as String;
      expect(RegExp(r'^[0-9a-f-]{16,64}$').hasMatch(deviceId), isTrue);
    });

    test('the device id is generated once and then reused', () async {
      await service.record(ProductEvent.scanStarted);
      await service.flush();
      final String first = remote.uploaded.first['device_id'] as String;

      now = now.add(const Duration(days: 1));
      await service.record(ProductEvent.scanStarted);
      await service.flush();

      expect(remote.uploaded.last['device_id'], first);
    });
  });

  group('consent', () {
    test('should default to on — this is opt-out (D-15)', () async {
      expect(await service.isEnabled(), isTrue);
    });

    // "Off" has to mean the backlog goes too. Leaving it would make the
    // switch a promise about the future only.
    test('opting out should delete what was already collected', () async {
      await service.record(ProductEvent.scanStarted);
      expect(await db.productEventDao.getAll(), hasLength(1));

      await service.setEnabled(enabled: false);

      expect(await db.productEventDao.getAll(), isEmpty);
      expect(await service.isEnabled(), isFalse);
    });

    test('opting back in should resume collection', () async {
      await service.setEnabled(enabled: false);
      await service.setEnabled(enabled: true);

      await service.record(ProductEvent.scanStarted);

      expect(await db.productEventDao.getAll(), hasLength(1));
    });
  });

  group('sync-driven upload', () {
    test('should flush when a sync run completes', () async {
      await service.record(ProductEvent.scanStarted);
      service.start();

      sync
        ..emit(const SyncPhaseSyncing())
        ..emit(const SyncPhaseSynced());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(remote.uploaded, hasLength(1));
    });

    // A settled `Synced` is what the stream replays to every new subscriber,
    // so keying on the phase alone would flush merely because something
    // started listening.
    test('should not flush on a Synced phase that follows no run', () async {
      await service.record(ProductEvent.scanStarted);
      service.start();

      sync.emit(const SyncPhaseSynced());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(remote.calls, 0);
    });

    test('should not flush when the run ended with rows still pending',
        () async {
      await service.record(ProductEvent.scanStarted);
      service.start();

      sync
        ..emit(const SyncPhaseSyncing())
        ..emit(const SyncPhasePending(count: 3));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(remote.calls, 0);
    });

    test('dispose should stop the listener', () async {
      service.start();
      await service.dispose();

      await service.record(ProductEvent.scanStarted);
      sync
        ..emit(const SyncPhaseSyncing())
        ..emit(const SyncPhaseSynced());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(remote.calls, 0);
    });
  });

  group('sign-out', () {
    test('clearUserData should wipe counters and rotate the device id',
        () async {
      await service.record(ProductEvent.scanStarted);
      await service.flush();
      final String before = remote.uploaded.single['device_id'] as String;

      await db.clearUserData();

      expect(await db.productEventDao.getAll(), isEmpty);
      expect(
        await db.userSettingsDao.getValue(TelemetryServiceImpl.kDeviceIdKey),
        isNull,
      );

      // The next account gets a fresh install id, so the server cannot link
      // the two accounts to one device.
      await service.record(ProductEvent.scanStarted);
      await service.flush();
      expect(remote.uploaded.last['device_id'], isNot(before));
    });

    test('clearUserData should not turn telemetry back on', () async {
      await service.setEnabled(enabled: false);

      await db.clearUserData();

      expect(await service.isEnabled(), isFalse);
    });

    test('a pending counter is dropped by sign-out rather than sent later',
        () async {
      await service.record(ProductEvent.scanStarted);
      expect(await db.productEventDao.getPendingSync(), hasLength(1));

      await db.clearUserData();

      expect(await service.flush(), 0);
      expect(remote.uploaded, isEmpty);
    });
  });

  group('batching', () {
    test('should cap one flush and carry the remainder to the next', () async {
      // One counter per day, past the per-flush cap.
      for (int i = 0; i < TelemetryServiceImpl.kMaxRowsPerFlush + 5; i++) {
        await db.productEventDao.increment(
          eventKey: 'scan_started',
          day: DateTime.utc(2025, 1, 1)
              .add(Duration(days: i))
              .toIso8601String()
              .split('T')
              .first,
        );
      }

      final int first = await service.flush();
      expect(first, TelemetryServiceImpl.kMaxRowsPerFlush);

      // Retention pruning removes the uploaded ones, leaving the remainder.
      expect(await db.productEventDao.getPendingSync(), hasLength(5));
    });
  });

  group('SyncStatus contract', () {
    test('a fresh counter is pending and a flushed one is not', () async {
      await service.record(ProductEvent.scanStarted);
      ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(SyncStatus.pending, contains(row.syncStatus));

      await service.flush();
      row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(row.syncStatus, SyncStatus.synced);
    });
  });
}
