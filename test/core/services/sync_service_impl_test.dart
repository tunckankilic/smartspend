import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
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
    // Default: an authenticated session, nothing to pull.
    when(() => remote.currentUserId).thenReturn('user-test-1');
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

    test('should stamp the session user id onto pushed rows', () async {
      // Locally created rows carry a null user_id; push must fill it from the
      // session so Postgres RLS (auth.uid() = user_id) accepts the insert.
      await insertPendingCategory();
      when(() => remote.upsert('categories', any()))
          .thenAnswer((_) async => 'cat-remote-1');

      await service.push();

      final List<dynamic> captured =
          verify(() => remote.upsert('categories', captureAny())).captured;
      final Map<String, dynamic> payload =
          captured.single as Map<String, dynamic>;
      expect(payload['user_id'], 'user-test-1');
    });

    test('should skip push entirely when no session is active', () async {
      // The startup sync can fire before sign-in; with no uid nothing can
      // satisfy RLS, so push must no-op instead of failing every row.
      when(() => remote.currentUserId).thenReturn(null);
      await insertPendingCategory();

      final Either<Failure, SyncReport> result = await service.push();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pushed, 0);
      expect(report.failed, 0);
      verifyNever(() => remote.upsert(any(), any()));
      expect(await db.categoryDao.getPendingSync(), hasLength(1));
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

    test('should not run or advance the watermark with no session', () async {
      // A pre-sign-in pull (startup timer / connectivity) must not touch the
      // watermark. If it stamped lastSyncAt=now, the real pull right after
      // sign-in would fetch `updated_at > now` and rehydrate nothing on a
      // fresh install / re-login — the empty-dashboard bug.
      when(() => remote.currentUserId).thenReturn(null);
      expect(await db.syncDao.getLastSyncAt(), isNull);

      final Either<Failure, SyncReport> result = await service.pull();

      final SyncReport report =
          result.getOrElse(() => throw StateError('expected Right'));
      expect(report.pulled, 0);
      expect(await db.syncDao.getLastSyncAt(), isNull);
      verifyNever(() => remote.fetchSince(any(), any()));
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

  String nowIso() => DateTime.now().toUtc().toIso8601String();

  group('push — all entity types in foreign-key order', () {
    test('should push every pending entity and resolve child FKs', () async {
      // Children reference this category / receipt; FK order guarantees the
      // parent gets a remoteId before the child is upserted in the same pass.
      final int catId = await insertPendingCategory();
      final int receiptId = await db.receiptDao.insertReceipt(
        ReceiptsCompanion.insert(
          storeName: const Value<String?>('Migros'),
          date: DateTime.utc(2026, 5, 1),
          total: 5000,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await db.receiptDao.insertItem(
        ReceiptItemsCompanion.insert(
          receiptId: receiptId,
          name: 'Süt',
          unitPrice: 1500,
          totalPrice: 3000,
          categoryId: Value<int?>(catId),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await db.into(db.tags).insert(
            TagsCompanion.insert(
              name: 'work',
              updatedAt: DateTime.now().toUtc(),
              syncStatus: const Value<String>(SyncStatus.pendingCreate),
            ),
          );
      await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          amount: 2500,
          categoryId: catId,
          receiptId: Value<int?>(receiptId),
          date: DateTime.utc(2026, 5, 1),
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await db.budgetDao.insertBudget(
        BudgetsCompanion.insert(
          categoryId: Value<int?>(catId),
          amount: 100000,
          period: 'monthly',
          startDate: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await db.userCorrectionDao.upsertCorrection(
        storeName: 'Migros',
        oldCategoryId: null,
        newCategoryId: catId,
        occurredAt: DateTime.utc(2026, 5, 1),
      );

      when(() => remote.upsert(any(), any())).thenAnswer(
        (Invocation i) async =>
            '${i.positionalArguments[0] as String}-remote',
      );

      final SyncReport report = (await service.push())
          .getOrElse(() => throw StateError('expected Right'));

      // category, receipt, item, tag, expense, budget, correction.
      expect(report.pushed, 7);
      expect(report.failed, 0);
      verify(() => remote.upsert('receipts', any())).called(1);
      verify(() => remote.upsert('receipt_items', any())).called(1);
      verify(() => remote.upsert('expenses', any())).called(1);
      verify(() => remote.upsert('budgets', any())).called(1);
      verify(() => remote.upsert('user_corrections', any())).called(1);
    });
  });

  group('push — deletes', () {
    Future<void> seedSyncedReceipt() => db.syncDao.applyReceiptFromRemote(
          remoteId: 'rcpt-r',
          date: DateTime.utc(2026, 5, 1),
          total: 100,
          currency: 'TRY',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

    test('should delete a soft-deleted receipt remotely then hard-delete',
        () async {
      await seedSyncedReceipt();
      final int id = (await db.syncDao.findReceiptByRemoteId('rcpt-r'))!.id;
      await db.receiptDao.softDeleteReceipt(id);
      when(() => remote.deleteById('receipts', 'rcpt-r'))
          .thenAnswer((_) async {});

      final SyncReport report = (await service.push())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.pushed, 1);
      verify(() => remote.deleteById('receipts', 'rcpt-r')).called(1);
      expect(await db.syncDao.findReceiptByRemoteId('rcpt-r'), isNull);
    });

    test('should keep the row pending when the remote delete fails', () async {
      await seedSyncedReceipt();
      final int id = (await db.syncDao.findReceiptByRemoteId('rcpt-r'))!.id;
      await db.receiptDao.softDeleteReceipt(id);
      when(() => remote.deleteById('receipts', 'rcpt-r'))
          .thenThrow(Exception('network'));

      final SyncReport report = (await service.push())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.failed, 1);
      expect(await db.syncDao.findReceiptByRemoteId('rcpt-r'), isNotNull);
      expect(await db.syncLogDao.failures(), isNotEmpty);
    });
  });

  group('push — unresolved parent foreign keys', () {
    test('should fail an expense whose category has no remoteId', () async {
      // A synced category with a null remoteId: not pending (never pushed),
      // so the child expense cannot resolve its parent's remote UUID.
      final int catId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'Orphan',
              icon: 'help',
              color: 1,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      await db.expenseDao.insertExpense(
        ExpensesCompanion.insert(
          amount: 100,
          categoryId: catId,
          date: DateTime.utc(2026, 5, 1),
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final SyncReport report = (await service.push())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.pushed, 0);
      expect(report.failed, 1);
      verifyNever(() => remote.upsert('expenses', any()));
    });

    test('should fail a receipt item whose receipt has no remoteId', () async {
      final int receiptId = await db.into(db.receipts).insert(
            ReceiptsCompanion.insert(
              date: DateTime.utc(2026, 5, 1),
              total: 100,
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
              // synced, no remoteId → not pushed, child cannot resolve parent.
            ),
          );
      await db.receiptDao.insertItem(
        ReceiptItemsCompanion.insert(
          receiptId: receiptId,
          name: 'Ekmek',
          unitPrice: 500,
          totalPrice: 500,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final SyncReport report = (await service.push())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.failed, 1);
      verifyNever(() => remote.upsert('receipt_items', any()));
    });
  });

  group('pull — expenses, budgets, conflicts', () {
    setUp(() {
      when(() => remote.fetchSince('categories', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cat-r',
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
    });

    test('should fold expenses and budgets resolving category FK', () async {
      when(() => remote.fetchSince('expenses', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'exp-r',
            'amount': 4200,
            'category_id': 'cat-r',
            'receipt_id': null,
            'note': 'lunch',
            'date': nowIso(),
            'is_manual': true,
            'is_recurring': false,
            'recurring_period': null,
            'created_at': nowIso(),
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );
      when(() => remote.fetchSince('budgets', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'bud-r',
            'amount': 50000,
            'period': 'monthly',
            // full timestamp exercises the non-bare-date parse branch.
            'start_date': nowIso(),
            'is_active': true,
            'category_id': 'cat-r',
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );

      final SyncReport report = (await service.pull())
          .getOrElse(() => throw StateError('expected Right'));

      // category + expense + budget.
      expect(report.pulled, 3);
      expect(await db.syncDao.findExpenseByRemoteId('exp-r'), isNotNull);
      expect(await db.syncDao.findBudgetByRemoteId('bud-r'), isNotNull);
    });

    test('should record a conflict when the local row is newer', () async {
      // Local copy carries a far-future updated_at; the incoming remote row
      // is older, so last-write-wins keeps local and logs a conflict.
      await db.syncDao.applyCategoryFromRemote(
        remoteId: 'cat-r',
        name: 'Local',
        icon: 'star',
        color: 1,
        isCustom: true,
        sortOrder: 1,
        updatedAt: DateTime.utc(2999),
      );

      final SyncReport report = (await service.pull())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.conflicts, greaterThanOrEqualTo(1));
      // Local name preserved.
      expect(
        (await db.syncDao.findCategoryByRemoteId('cat-r'))!.name,
        'Local',
      );
    });

    test('should skip an expense whose category is absent locally', () async {
      when(() => remote.fetchSince('categories', any()))
          .thenAnswer((_) async => <Map<String, dynamic>>[]);
      when(() => remote.fetchSince('expenses', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'exp-orphan',
            'amount': 100,
            'category_id': 'cat-missing',
            'receipt_id': null,
            'note': null,
            'date': nowIso(),
            'is_manual': true,
            'is_recurring': false,
            'recurring_period': null,
            'created_at': nowIso(),
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );

      final SyncReport report = (await service.pull())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.pulled, 0);
      expect(await db.syncDao.findExpenseByRemoteId('exp-orphan'), isNull);
    });
  });

  group('lifecycle', () {
    test('start should be idempotent and wire connectivity changes', () async {
      final StreamController<List<ConnectivityResult>> conn =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => conn.stream);

      // The second start() is a no-op.
      service
        ..start()
        ..start();

      conn.add(<ConnectivityResult>[ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final SyncPhase phase = await service.watchStatus().first;
      expect(phase, isA<SyncPhaseOffline>());
      await conn.close();
    });

    test('connectivity restored should trigger a sync', () async {
      final StreamController<List<ConnectivityResult>> conn =
          StreamController<List<ConnectivityResult>>.broadcast();
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => conn.stream);

      service.start();
      conn.add(<ConnectivityResult>[ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      verify(() => remote.fetchSince('categories', any())).called(1);
      await conn.close();
    });
  });
}
