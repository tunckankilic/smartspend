// Offline-first integration skeleton (Sprint 8.3 / A7).
//
// These tests exercise the real Drift database wired to the real
// `SupabaseSyncServiceImpl`, with only the network edge (the
// `SyncRemoteDataSource` + `Connectivity`) mocked. They cover the five
// critical offline-first flows the transfer doc calls out:
//
//   1. Capture data while "offline", then drain the queue once "online".
//   2. Sign-out wipes the local cache (`AppDatabase.clearUserData`).
//   3. Pull folds a brand-new server expense into the local cache.
//   4. A stale remote update loses to the newer local row (last-write-wins
//      conflict resolution) and is logged as a conflict.
//   5. A per-row push failure is isolated: the row stays pending and the
//      batch still reports success for the rest.
//
// HOW TO RUN
// ----------
//   flutter test integration_test/offline_sync_flow_test.dart -d <device>
//
// A device/simulator is required because this uses the integration_test
// binding. If no simulator is available in CI, run these MANUALLY on a
// local device; they are intentionally network-free so they need no
// Supabase project.
//
// A full UI end-to-end (booting `SmartSpendApp`) additionally needs a live
// Supabase test project + an authenticated session, so that variant is left
// as a documented manual step rather than a CI gate.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/sync_remote_data_source.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/services/sync_service_impl.dart';

class _MockRemote extends Mock implements SyncRemoteDataSource {}

class _MockConnectivity extends Mock implements Connectivity {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _MockRemote remote;
  late _MockConnectivity connectivity;
  late SupabaseSyncServiceImpl service;
  late int categoryId;
  late String categoryRemoteId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Force `onCreate` so the default categories are seeded.
    final List<Category> categories = await db.categoryDao.getAll();
    categoryId = categories.first.id;
    final String? seedRemoteId = categories.first.remoteId;
    categoryRemoteId = seedRemoteId ??
        (throw StateError('seed category is missing a remoteId'));

    remote = _MockRemote();
    connectivity = _MockConnectivity();
    service = SupabaseSyncServiceImpl(
      database: db,
      remote: remote,
      connectivity: connectivity,
    );
    // Default: server has nothing new to hand back on pull.
    when(() => remote.fetchSince(any(), any()))
        .thenAnswer((_) async => <Map<String, dynamic>>[]);
  });

  tearDown(() async {
    await service.dispose();
    await db.close();
  });

  Future<void> insertExpense(int amountMinor) async {
    await db.expenseDao.insertExpense(
      ExpensesCompanion.insert(
        amount: amountMinor,
        categoryId: categoryId,
        date: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        isManual: const Value<bool>(true),
      ),
    );
  }

  testWidgets(
    'should queue 5 offline expenses and push them all once online',
    (WidgetTester tester) async {
      // --- Offline: capture five expenses. ---
      for (int i = 0; i < 5; i++) {
        await insertExpense(1000 + i);
      }
      expect(await db.expenseDao.getPendingSync(), hasLength(5));

      // --- Online: the server accepts each upsert. ---
      when(() => remote.upsert('expenses', any()))
          .thenAnswer((_) async => 'exp-remote');

      final Either<Failure, SyncReport> result = await service.sync();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pushed, 5);
      expect(report.failed, 0);
      expect(await db.expenseDao.getPendingSync(), isEmpty);
    },
  );

  testWidgets(
    'should clear local data on sign-out',
    (WidgetTester tester) async {
      await insertExpense(2500);
      await db.categoryDao.insertCustom(
        CategoriesCompanion.insert(
          name: 'Hobi',
          icon: 'star',
          color: 0xFF00FF00,
          sortOrder: const Value<int>(99),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      expect(await db.expenseDao.getPendingSync(), isNotEmpty);

      // The AuthBloc calls this after a successful sign-out / delete.
      await db.clearUserData();

      expect(await db.expenseDao.getPendingSync(), isEmpty);
      // Custom categories are wiped; the seeded defaults remain.
      final List<Category> remaining = await db.categoryDao.getAll();
      expect(remaining.any((Category c) => c.isCustom), isFalse);
    },
  );

  testWidgets(
    'should pull a new server expense into the local cache',
    (WidgetTester tester) async {
      expect(await db.expenseDao.getPendingSync(), isEmpty);
      final DateTime now = DateTime.now().toUtc();

      when(() => remote.fetchSince('expenses', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'exp-server-1',
            'user_id': 'user-1',
            'amount': 4200,
            'category_id': categoryRemoteId,
            'receipt_id': null,
            'note': 'from server',
            'date': now.toIso8601String(),
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'is_manual': true,
            'is_recurring': false,
            'recurring_period': null,
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pulled, 1);
      expect(report.conflicts, 0);

      final List<Expense> local =
          await db.expenseDao.getByCategory(categoryId);
      expect(local, hasLength(1));
      expect(local.single.amount, 4200);
      // A pulled row arrives already-synced, not queued for push.
      expect(await db.expenseDao.getPendingSync(), isEmpty);
    },
  );

  testWidgets(
    'should reject a stale remote update and log it as a conflict',
    (WidgetTester tester) async {
      // The seeded category was written with `updatedAt == now`; a remote
      // copy stamped in the past must lose the last-write-wins comparison.
      final DateTime stale = DateTime.utc(2000);

      when(() => remote.fetchSince('categories', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': categoryRemoteId,
            'user_id': null,
            'name': 'STALE NAME',
            'icon': 'star',
            'color': 0xFF000000,
            'is_custom': false,
            'sort_order': 0,
            'updated_at': stale.toIso8601String(),
          },
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.conflicts, 1);

      // The local name survived — the stale remote write was discarded.
      final Category kept = (await db.categoryDao.getAll())
          .firstWhere((Category c) => c.remoteId == categoryRemoteId);
      expect(kept.name, isNot('STALE NAME'));
    },
  );

  testWidgets(
    'should keep a row pending when its remote push throws',
    (WidgetTester tester) async {
      await insertExpense(9900);
      expect(await db.expenseDao.getPendingSync(), hasLength(1));

      when(() => remote.upsert('expenses', any()))
          .thenThrow(Exception('boom'));

      final Either<Failure, SyncReport> result = await service.push();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.failed, 1);
      expect(report.pushed, 0);
      // The row was not lost; it stays queued for the next attempt.
      expect(await db.expenseDao.getPendingSync(), hasLength(1));
    },
  );
}
