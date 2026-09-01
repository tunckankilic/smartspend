import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
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
          remotePayload: <String, dynamic>{'id': 'rcpt-r'},
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
        remotePayload: <String, dynamic>{'id': 'cat-r'},
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

    test('should keep the remote version it discarded — two devices, one user',
        () async {
      // The scenario 1.3.0 exists for. Phone edits a category at a moment the
      // tablet has not seen; the tablet's older edit arrives on the next pull
      // and loses. Before this release the tablet's version was gone at that
      // instant, with `sync_log` recording only that *something* had been
      // discarded. Now the losing row survives in full, so 1.4.0 can show it
      // to the user and offer to replay it.
      await db.syncDao.applyCategoryFromRemote(
        remoteId: 'cat-r',
        remotePayload: <String, dynamic>{'id': 'cat-r'},
        name: 'Phone edit',
        icon: 'star',
        color: 1,
        isCustom: true,
        sortOrder: 1,
        updatedAt: DateTime.utc(2999),
        userId: 'user-1',
      );

      final SyncReport report = (await service.pull())
          .getOrElse(() => throw StateError('expected Right'));
      expect(report.conflicts, greaterThanOrEqualTo(1));

      final List<SyncConflictPayload> quarantined =
          await db.syncDao.getConflictPayloads();
      expect(quarantined, hasLength(1));

      final SyncConflictPayload row = quarantined.single;
      expect(row.conflictTableName, 'categories');
      expect(row.remoteId, 'cat-r');
      expect(row.userId, 'user-1');
      expect(row.localUpdatedAt.toUtc(), DateTime.utc(2999));
      expect(row.remoteUpdatedAt.isBefore(row.localUpdatedAt), isTrue);

      // The discarded row is recoverable field by field, not just countable.
      final Map<String, dynamic> lost =
          jsonDecode(row.remotePayload) as Map<String, dynamic>;
      expect(lost['id'], 'cat-r');
      expect(lost['name'], 'Seyahat');
      expect(lost['icon'], 'flight');
      expect(lost['color'], 0xFF112233);
      expect(lost['sort_order'], 50);
      expect(lost['is_custom'], isTrue);

      // And the winner is still the winner — this release stops the loss, it
      // does not resolve the conflict.
      expect(
        (await db.syncDao.findCategoryByRemoteId('cat-r'))!.name,
        'Phone edit',
      );
    });

    test('should defer, not drop, an expense whose category is absent locally',
        () async {
      // The row is not applied — its category is not here, so there is no
      // valid local FK to write. But `pull()` advances `last_sync_at` to now
      // regardless, and the next `fetchSince` asks for `updated_at > now`, so
      // a bare skip meant this device never asked for the row again. It stayed
      // safe on the server and invisible on the phone. Now it is held.
      when(() => remote.fetchSince('categories', any()))
          .thenAnswer((_) async => <Map<String, dynamic>>[]);
      when(() => remote.fetchSince('expenses', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'exp-orphan',
            'amount': 100,
            'category_id': 'cat-missing',
            'receipt_id': null,
            'note': 'oglen yemegi',
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
      expect(report.deferred, 1);
      expect(await db.syncDao.findExpenseByRemoteId('exp-orphan'), isNull);

      final List<SyncDeferredRow> held = await db.syncDao.getDeferredRows();
      expect(held, hasLength(1));
      expect(held.single.deferredTableName, 'expenses');
      expect(held.single.remoteId, 'exp-orphan');
      expect(held.single.userId, 'user-1');
      // What it is waiting for, so 1.4.0 knows when to retry.
      expect(held.single.missingParentTable, 'categories');
      expect(held.single.missingParentRemoteId, 'cat-missing');

      final Map<String, dynamic> payload =
          jsonDecode(held.single.remotePayload) as Map<String, dynamic>;
      expect(payload['amount'], 100);
      expect(payload['note'], 'oglen yemegi');
      expect(payload['category_id'], 'cat-missing');
    });

    test('should defer a receipt item whose receipt is absent locally',
        () async {
      when(() => remote.fetchSince('receipts', any()))
          .thenAnswer((_) async => <Map<String, dynamic>>[]);
      when(() => remote.fetchSince('receipt_items', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'item-orphan',
            'receipt_id': 'rcpt-missing',
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

      final SyncReport report = (await service.pull())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.deferred, 1);
      final List<SyncDeferredRow> held = await db.syncDao.getDeferredRows();
      expect(held.single.deferredTableName, 'receipt_items');
      expect(held.single.missingParentTable, 'receipts');
      expect(held.single.missingParentRemoteId, 'rcpt-missing');
    });

    test('should defer a user correction whose category is absent locally',
        () async {
      when(() => remote.fetchSince('categories', any()))
          .thenAnswer((_) async => <Map<String, dynamic>>[]);
      when(() => remote.fetchSince('user_corrections', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'corr-orphan',
            'store_name': 'Migros',
            'old_category_id': null,
            'new_category_id': 'cat-missing',
            'count': 3,
            'occurred_at': nowIso(),
            'updated_at': nowIso(),
            'user_id': 'user-1',
          },
        ],
      );

      final SyncReport report = (await service.pull())
          .getOrElse(() => throw StateError('expected Right'));

      expect(report.deferred, 1);
      final List<SyncDeferredRow> held = await db.syncDao.getDeferredRows();
      expect(held.single.deferredTableName, 'user_corrections');
      expect(held.single.missingParentTable, 'categories');
      expect(held.single.missingParentRemoteId, 'cat-missing');
    });

    test('a deferred row is written to sync_log too, so it is visible',
        () async {
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

      await service.pull();

      final List<SyncLogData> entries = await db.syncLogDao.recent();
      expect(
        entries.where(
          (SyncLogData e) =>
              e.operation == SyncOperation.deferredMissingParent &&
              e.recordId == 'exp-orphan',
        ),
        hasLength(1),
      );
    });

    test('re-pulling the same orphan replaces it instead of piling up',
        () async {
      // A watermark reset (sign-out, fresh install) re-pulls the whole
      // history. The same orphan must not accumulate a row per full pull.
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

      await service.pull();
      await service.pull();
      await service.pull();

      expect(await db.syncDao.getDeferredRows(), hasLength(1));
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

  group('tax profile sync', () {
    Map<String, dynamic> remoteProfile({
      String id = 'profile-remote-1',
      String legalForm = 'limited',
      String? updatedAt,
    }) =>
        <String, dynamic>{
          'id': id,
          'user_id': 'user-test-1',
          'legal_form': legalForm,
          'vat_liability': 'monthly',
          'withholding_liability': 'unknown',
          'employs_staff': 'yes',
          'bagkur_insured': 'unknown',
          'uses_e_ledger': 'no',
          'owns_vehicle': 'unknown',
          'owns_real_estate': 'unknown',
          'created_at': DateTime.utc(2026, 9, 1).toIso8601String(),
          'updated_at':
              updatedAt ?? DateTime.now().toUtc().toIso8601String(),
        };

    test('should push a pending profile against the user_id constraint',
        () async {
      // Not the `id` primary key: a device that filled the wizard offline has
      // no server id to conflict on, and the table is unique on user_id. With
      // the wrong target that push fails forever or duplicates the profile.
      await db.taxProfileDao.save(
        const TaxpayerProfile(
          legalForm: TaxpayerLegalForm.limited,
          employsStaff: TaxpayerAnswer.yes,
        ),
      );
      when(
        () => remote.upsert(
          'tax_profiles',
          any(),
          onConflict: any(named: 'onConflict'),
        ),
      ).thenAnswer((_) async => 'profile-remote-1');

      final Either<Failure, SyncReport> result = await service.push();

      expect(
        result.getOrElse(() => throw StateError('expected Right')).failed,
        0,
      );
      final List<dynamic> captured = verify(
        () => remote.upsert(
          'tax_profiles',
          captureAny(),
          onConflict: captureAny(named: 'onConflict'),
        ),
      ).captured;
      final Map<String, dynamic> payload =
          captured.first as Map<String, dynamic>;
      expect(captured.last, 'user_id');
      expect(payload['user_id'], 'user-test-1');
      expect(payload['legal_form'], 'limited');
      expect(payload['employs_staff'], 'yes');
      expect(payload['owns_vehicle'], 'unknown');
      expect((await db.taxProfileDao.getRow())!.remoteId, 'profile-remote-1');
      expect(await db.taxProfileDao.getPendingSync(), isEmpty);
    });

    test('should apply a pulled profile on a device that has none', () async {
      when(() => remote.fetchSince('tax_profiles', any()))
          .thenAnswer((_) async => <Map<String, dynamic>>[remoteProfile()]);

      final Either<Failure, SyncReport> result = await service.pull();

      expect(
        result.getOrElse(() => throw StateError('expected Right')).pulled,
        greaterThan(0),
      );
      final TaxpayerProfile stored = await db.taxProfileDao.getProfile();
      expect(stored.legalForm, TaxpayerLegalForm.limited);
      expect(stored.employsStaff, TaxpayerAnswer.yes);
    });

    test('should adopt the local offline profile instead of adding a second',
        () async {
      // The tablet filled the wizard while offline, so its row has no
      // remote_id. Inserting the server's copy alongside it would leave the
      // device holding two profiles with no rule for which one generates the
      // calendar.
      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.sahisSirketi),
        now: DateTime.utc(2026, 9, 1, 8),
      );
      when(() => remote.fetchSince('tax_profiles', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          remoteProfile(
            updatedAt: DateTime.utc(2026, 9, 1, 12).toIso8601String(),
          ),
        ],
      );

      await service.pull();

      final List<TaxProfile> rows = await db.select(db.taxProfiles).get();
      expect(rows, hasLength(1));
      expect(rows.single.remoteId, 'profile-remote-1');
      expect(rows.single.legalForm, 'limited');
    });

    test('should keep the answers last-write-wins is about to discard',
        () async {
      // Wizard answered on the phone at 12:00 and on the tablet at 08:00.
      // The older set loses — but it is the user's answer about their own
      // business, and 1.3.0's whole point is that a losing version is kept
      // rather than dropped on the floor.
      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.anonim),
        now: DateTime.utc(2026, 9, 1, 12),
      );
      when(() => remote.fetchSince('tax_profiles', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          remoteProfile(
            updatedAt: DateTime.utc(2026, 9, 1, 8).toIso8601String(),
          ),
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      expect(
        result.getOrElse(() => throw StateError('expected Right')).conflicts,
        1,
      );
      expect((await db.taxProfileDao.getRow())!.legalForm, 'anonim');
      final List<SyncConflictPayload> quarantined =
          await db.syncDao.getConflictPayloads();
      expect(quarantined, hasLength(1));
      expect(quarantined.single.conflictTableName, 'tax_profiles');
      expect(quarantined.single.remotePayload, contains('limited'));
    });

    test('should count a pending profile as work still to do', () async {
      expect(await service.pendingCount(), 0);

      await db.taxProfileDao.save(
        const TaxpayerProfile(usesELedger: TaxpayerAnswer.yes),
      );

      expect(await service.pendingCount(), 1);
    });
  });


  group('tax obligation sync', () {
    Future<int> generateAugustVat({DateTime? now}) =>
        db.taxObligationDao.upsertGenerated(
          generationKey: 'kdv1|2026-08-01|0',
          kind: 'kdv1',
          periodKind: 'monthly',
          periodStart: DateTime.utc(2026, 8),
          periodEnd: DateTime.utc(2026, 8, 31),
          declarationDueDate: DateTime.utc(2026, 9, 28),
          now: now,
        );

    Map<String, dynamic> remoteObligation({
      String id = 'obl-remote-1',
      String? note,
      String? updatedAt,
    }) =>
        <String, dynamic>{
          'id': id,
          'user_id': 'user-test-1',
          'generation_key': 'kdv1|2026-08-01|0',
          'kind': 'kdv1',
          'period_kind': 'monthly',
          'period_start': '2026-08-01',
          'period_end': '2026-08-31',
          'installment_index': 0,
          'declaration_due_date': '2026-09-28',
          'payment_due_date': null,
          'due_date_source': 'catalog',
          'amount_minor': null,
          'amount_source': 'unknown',
          'declared_at': null,
          'paid_at': null,
          'dismissed_at': null,
          'note': note,
          'title': null,
          'is_user_defined': false,
          'created_at': DateTime.utc(2026, 9).toIso8601String(),
          'updated_at':
              updatedAt ?? DateTime.now().toUtc().toIso8601String(),
        };

    test('should push a generated item as a date, not a timestamp', () async {
      // The server column is `date`. Sending a timestamp would let the
      // device's timezone shift a filing deadline by a day.
      await generateAugustVat();
      when(
        () => remote.upsert(
          'tax_obligations',
          any(),
          onConflict: any(named: 'onConflict'),
        ),
      ).thenAnswer((_) async => 'obl-remote-1');

      await service.push();

      final List<dynamic> captured = verify(
        () => remote.upsert(
          'tax_obligations',
          captureAny(),
          onConflict: captureAny(named: 'onConflict'),
        ),
      ).captured;
      final Map<String, dynamic> payload =
          captured.first as Map<String, dynamic>;
      expect(captured.last, 'user_id,generation_key');
      expect(payload['period_start'], '2026-08-01');
      expect(payload['declaration_due_date'], '2026-09-28');
      expect(payload['payment_due_date'], isNull);
      expect(payload['amount_source'], 'unknown');
    });

    test('should merge a pulled item onto the one generated locally',
        () async {
      // Both devices generated August's return; neither has the other's id.
      // Without the generation-key match the user would see the same deadline
      // twice.
      await generateAugustVat(now: DateTime.utc(2026, 9, 1, 8));
      when(() => remote.fetchSince('tax_obligations', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          remoteObligation(
            note: 'muhasebeci: 28i',
            updatedAt: DateTime.utc(2026, 9, 1, 12).toIso8601String(),
          ),
        ],
      );

      await service.pull();

      final List<TaxObligation> all = await db.taxObligationDao.getAll();
      expect(all, hasLength(1));
      expect(all.single.remoteId, 'obl-remote-1');
      expect(all.single.note, 'muhasebeci: 28i');
    });

    test('should keep the item version last-write-wins discards', () async {
      await generateAugustVat(now: DateTime.utc(2026, 9, 1, 12));
      when(() => remote.fetchSince('tax_obligations', any())).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          remoteObligation(
            note: 'ödendi diye işaretledim',
            updatedAt: DateTime.utc(2026, 9, 1, 8).toIso8601String(),
          ),
        ],
      );

      final Either<Failure, SyncReport> result = await service.pull();

      expect(
        result.getOrElse(() => throw StateError('expected Right')).conflicts,
        1,
      );
      final List<SyncConflictPayload> quarantined =
          await db.syncDao.getConflictPayloads();
      expect(quarantined.single.conflictTableName, 'tax_obligations');
      expect(
        quarantined.single.remotePayload,
        contains('ödendi diye işaretledim'),
      );
    });

    test('should pull an item that has no deadline yet', () async {
      // The normal state while the catalog is unverified: a null due date has
      // to survive the round trip rather than becoming a date.
      final Map<String, dynamic> row = remoteObligation()
        ..['declaration_due_date'] = null;
      when(() => remote.fetchSince('tax_obligations', any()))
          .thenAnswer((_) async => <Map<String, dynamic>>[row]);

      await service.pull();

      final TaxObligation stored = (await db.taxObligationDao.getAll()).single;
      expect(stored.declarationDueDate, isNull);
      expect(stored.paymentDueDate, isNull);
    });

    test('should pin a pulled date to UTC midnight', () async {
      when(() => remote.fetchSince('tax_obligations', any()))
          .thenAnswer((_) async => <Map<String, dynamic>>[remoteObligation()]);

      await service.pull();

      final TaxObligation stored = (await db.taxObligationDao.getAll()).single;
      expect(stored.declarationDueDate, DateTime.utc(2026, 9, 28));
      expect(stored.declarationDueDate!.isUtc, isTrue);
    });

    test('should count a pending item as work still to do', () async {
      await generateAugustVat();

      expect(await service.pendingCount(), 1);
    });
  });

}
