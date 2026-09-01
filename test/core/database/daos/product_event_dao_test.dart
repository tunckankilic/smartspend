import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  group('ProductEventDao.increment', () {
    test("should create the day's first counter at 1", () async {
      await db.productEventDao.increment(
        eventKey: 'scan_started',
        day: '2026-09-01',
      );

      final ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(row.count, 1);
      expect(row.dimension, '');
      expect(row.syncStatus, SyncStatus.pendingCreate);
      // companyId stays null for all of 1.3.0 — the companies table is 1.4.0.
      expect(row.companyId, isNull);
    });

    test('should add to the existing counter rather than replace it', () async {
      for (int i = 0; i < 3; i++) {
        await db.productEventDao.increment(
          eventKey: 'scan_started',
          day: '2026-09-01',
        );
      }

      final ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(row.count, 3);
      expect(await db.productEventDao.getAll(), hasLength(1));
    });

    // Telemetry is recorded from UI callbacks that can overlap. A Dart-side
    // read-modify-write would drop increments here; the additive SQL upsert
    // is what makes concurrent calls safe.
    test('should not drop increments issued concurrently', () async {
      await Future.wait<void>(<Future<void>>[
        for (int i = 0; i < 20; i++)
          db.productEventDao.increment(
            eventKey: 'scan_started',
            day: '2026-09-01',
          ),
      ]);

      final ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(row.count, 20);
    });

    test('should keep separate counters per dimension', () async {
      await db.productEventDao.increment(
        eventKey: 'tax_profile_completed',
        dimension: 'limited',
        day: '2026-09-01',
      );
      await db.productEventDao.increment(
        eventKey: 'tax_profile_completed',
        dimension: 'sahis_sirketi',
        day: '2026-09-01',
      );

      expect(await db.productEventDao.getAll(), hasLength(2));
      expect(
        (await db.productEventDao.find(
          eventKey: 'tax_profile_completed',
          dimension: 'limited',
          day: '2026-09-01',
        ))!
            .count,
        1,
      );
    });

    test('should keep separate counters per day', () async {
      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-01');
      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-02');

      expect(await db.productEventDao.getAll(), hasLength(2));
    });

    test('should flip a synced counter back to pending', () async {
      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-01');
      final ProductEventCounter first = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      await db.productEventDao
          .markUploaded(id: first.id, uploadedCount: first.count);

      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-01');

      final ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(row.count, 2);
      expect(row.syncStatus, SyncStatus.pendingUpdate);
      expect(await db.productEventDao.getPendingSync(), hasLength(1));
    });
  });

  group('ProductEventDao.markUploaded', () {
    test('should stamp the row synced when the count still matches', () async {
      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-01');
      final ProductEventCounter row = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;

      final bool ok = await db.productEventDao.markUploaded(
        id: row.id,
        uploadedCount: row.count,
        remoteId: 'srv-1',
      );

      expect(ok, isTrue);
      final ProductEventCounter after = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(after.syncStatus, SyncStatus.synced);
      expect(after.remoteId, 'srv-1');
      expect(await db.productEventDao.getPendingSync(), isEmpty);
    });

    // The whole reason markUploaded is a compare-and-set. Stamping the row
    // synced unconditionally would swallow the increment that arrived while
    // the upload was in flight, and it would stay swallowed until some later
    // increment happened to push the row pending again.
    test('should leave the row pending when the count moved mid-upload',
        () async {
      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-01');
      final ProductEventCounter uploaded = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;

      // The user scans again while the request is in flight.
      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-01');

      final bool ok = await db.productEventDao.markUploaded(
        id: uploaded.id,
        uploadedCount: uploaded.count,
      );

      expect(ok, isFalse);
      final ProductEventCounter after = (await db.productEventDao.find(
        eventKey: 'scan_started',
        day: '2026-09-01',
      ))!;
      expect(after.count, 2);
      expect(after.syncStatus, SyncStatus.pendingUpdate);
      expect(await db.productEventDao.getPendingSync(), hasLength(1));
    });
  });

  group('ProductEventDao retention', () {
    test('deleteUploadedBefore should drop only synced, older rows', () async {
      Future<void> seed(String day, {required bool synced}) async {
        await db.productEventDao
            .increment(eventKey: 'scan_started', day: day);
        if (!synced) return;
        final ProductEventCounter row = (await db.productEventDao.find(
          eventKey: 'scan_started',
          day: day,
        ))!;
        await db.productEventDao
            .markUploaded(id: row.id, uploadedCount: row.count);
      }

      await seed('2026-08-01', synced: true); // old + uploaded → goes
      await seed('2026-08-02', synced: false); // old + pending  → stays
      await seed('2026-09-01', synced: true); // recent          → stays

      await db.productEventDao.deleteUploadedBefore('2026-08-25');

      final List<String> remaining = (await db.productEventDao.getAll())
          .map((ProductEventCounter c) => c.day)
          .toList()
        ..sort();
      expect(remaining, <String>['2026-08-02', '2026-09-01']);
    });

    test('deleteAll should empty the table', () async {
      await db.productEventDao
          .increment(eventKey: 'scan_started', day: '2026-09-01');
      await db.productEventDao
          .increment(eventKey: 'scan_approved', day: '2026-09-01');

      await db.productEventDao.deleteAll();

      expect(await db.productEventDao.getAll(), isEmpty);
    });
  });
}
