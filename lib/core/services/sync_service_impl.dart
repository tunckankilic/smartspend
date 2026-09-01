import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/sync_remote_data_source.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/supabase/supabase_error_mapper.dart';

/// Supabase-backed [SyncService].
///
/// Push walks the tables in foreign-key order (parents before children) so a
/// child's parent always has a remote UUID before the child is sent. Pull
/// folds remote changes into Drift, resolving divergence last-write-wins by
/// `updated_at`. Per-row push failures are isolated: they are logged to
/// `sync_log` and the row stays `pending_*` for the next run rather than
/// aborting the whole batch.
///
/// Last-write-wins still picks a winner, but as of 1.3.0 it no longer throws
/// the loser away: each discarded remote row is quarantined verbatim in
/// `sync_conflict_payloads` (see [SyncDao.recordConflictPayload]). Which is
/// why every `apply*FromRemote` call below hands the raw `row` down — the
/// unmapped wire JSON is what 1.4.0's resolution screen will replay.
class SupabaseSyncServiceImpl implements SyncService {
  SupabaseSyncServiceImpl({
    required this.database,
    required this.remote,
    required this.connectivity,
    this.interval = const Duration(minutes: 5),
  });

  final AppDatabase database;
  final SyncRemoteDataSource remote;
  final Connectivity connectivity;
  final Duration interval;

  final StreamController<SyncPhase> _phases =
      StreamController<SyncPhase>.broadcast();
  SyncPhase _phase = const SyncPhaseSynced();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;
  bool _started = false;
  bool _running = false;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  @override
  void start() {
    if (_started) return;
    _started = true;
    _connSub = connectivity.onConnectivityChanged.listen(_onConnectivity);
    _timer = Timer.periodic(interval, (_) {
      unawaited(sync());
    });
  }

  @override
  Future<void> dispose() async {
    await _connSub?.cancel();
    _timer?.cancel();
    await _phases.close();
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final bool online = results.any(
      (ConnectivityResult r) => r != ConnectivityResult.none,
    );
    if (!online) {
      _emit(const SyncPhaseOffline());
      return;
    }
    await sync();
  }

  // -----------------------------------------------------------------------
  // Status stream
  // -----------------------------------------------------------------------

  @override
  Stream<SyncPhase> watchStatus() async* {
    yield _phase;
    yield* _phases.stream;
  }

  void _emit(SyncPhase phase) {
    _phase = phase;
    if (!_phases.isClosed) _phases.add(phase);
  }

  Future<void> _refreshPhase() async {
    final int pending = await _pendingCount();
    if (pending > 0) {
      _emit(SyncPhasePending(count: pending));
    } else {
      final DateTime? lastSyncAt = await database.syncDao.getLastSyncAt();
      _emit(SyncPhaseSynced(lastSyncAt: lastSyncAt));
    }
  }

  @override
  Future<int> pendingCount() => _pendingCount();

  Future<int> _pendingCount() async {
    int n = 0;
    n += (await database.categoryDao.getPendingSync()).length;
    n += (await database.receiptDao.getPendingSync()).length;
    n += (await database.syncDao.getPendingReceiptItems()).length;
    n += (await database.syncDao.getPendingTags()).length;
    n += (await database.expenseDao.getPendingSync()).length;
    n += (await database.budgetDao.getPendingSync()).length;
    n += (await database.userCorrectionDao.getPendingSync()).length;
    n += (await database.taxProfileDao.getPendingSync()).length;
    n += (await database.taxObligationDao.getPendingSync()).length;
    return n;
  }

  // -----------------------------------------------------------------------
  // Orchestration
  // -----------------------------------------------------------------------

  @override
  Future<Either<Failure, SyncReport>> sync() async {
    if (_running) return const Right<Failure, SyncReport>(SyncReport());
    _running = true;
    _emit(const SyncPhaseSyncing());
    try {
      final Either<Failure, SyncReport> pushed = await push();
      return await pushed.fold(
        (Failure f) async => Left<Failure, SyncReport>(f),
        (SyncReport pushReport) async {
          final Either<Failure, SyncReport> pulled = await pull();
          return pulled.fold(
            Left<Failure, SyncReport>.new,
            (SyncReport pullReport) =>
                Right<Failure, SyncReport>(pushReport + pullReport),
          );
        },
      );
    } finally {
      _running = false;
      await _refreshPhase();
    }
  }

  // -----------------------------------------------------------------------
  // Push (Drift → Supabase), foreign-key order
  // -----------------------------------------------------------------------

  @override
  Future<Either<Failure, SyncReport>> push() async {
    try {
      // Locally created rows are born without an owner; stamp the active
      // session's uid so Postgres RLS (`auth.uid() = user_id`) accepts the
      // insert. Without a session (e.g. the startup sync before sign-in) no
      // write can satisfy RLS, so skip rather than logging a failure per row.
      final String? userId = remote.currentUserId;
      if (userId == null) {
        return const Right<Failure, SyncReport>(SyncReport());
      }

      int pushed = 0;
      int failed = 0;

      // 1. Categories (no parent).
      for (final Category c in await database.categoryDao.getPendingSync()) {
        try {
          final String id = await remote.upsert('categories', <String, dynamic>{
            if (c.remoteId != null) 'id': c.remoteId,
            'user_id': userId,
            'name': c.name,
            'icon': c.icon,
            'color': c.color,
            'is_custom': c.isCustom,
            'sort_order': c.sortOrder,
          });
          await database.syncDao.markCategorySynced(c.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure('categories', c.remoteId ?? '${c.id}', e);
        }
      }

      // 2. Receipts (no syncable parent).
      for (final Receipt r in await database.receiptDao.getPendingSync()) {
        if (r.syncStatus == SyncStatus.pendingDelete) {
          if (await _pushDelete('receipts', r.remoteId)) {
            await database.syncDao.hardDeleteReceipt(r.id);
            pushed++;
          } else {
            failed++;
          }
          continue;
        }
        final DateTime? warranty = r.warrantyEndDate;
        try {
          final String id = await remote.upsert('receipts', <String, dynamic>{
            if (r.remoteId != null) 'id': r.remoteId,
            'user_id': userId,
            'store_name': r.storeName,
            'date': _dateOnly(r.date),
            'total': r.total,
            'currency': r.currency,
            'image_path': r.imagePath,
            'storage_object_path': r.storageObjectPath,
            'raw_ocr_text': r.rawOcrText,
            'confidence_score': r.confidenceScore,
            'warranty_end_date': warranty == null ? null : _dateOnly(warranty),
          });
          await database.syncDao.markReceiptSynced(r.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure('receipts', r.remoteId ?? '${r.id}', e);
        }
      }

      // 3. Receipt items (parent: receipts, category).
      final List<ReceiptItem> pendingItems = await database.syncDao
          .getPendingReceiptItems();
      for (final ReceiptItem item in pendingItems) {
        final String? receiptRemote = await database.syncDao.receiptRemoteId(
          item.receiptId,
        );
        if (receiptRemote == null) {
          failed++; // Parent not yet synced; retry next run.
          await _logFailure(
            'receipt_items',
            item.remoteId ?? '${item.id}',
            'receipt ${item.receiptId} has no remote id yet (parent unsynced)',
          );
          continue;
        }
        final int? localCat = item.categoryId;
        try {
          final String id = await remote.upsert(
            'receipt_items',
            <String, dynamic>{
              if (item.remoteId != null) 'id': item.remoteId,
              'user_id': userId,
              'receipt_id': receiptRemote,
              'name': item.name,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'total_price': item.totalPrice,
              'category_id': localCat == null
                  ? null
                  : await database.syncDao.categoryRemoteId(localCat),
            },
          );
          await database.syncDao.markReceiptItemSynced(item.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure('receipt_items', item.remoteId ?? '${item.id}', e);
        }
      }

      // 4. Tags (no parent).
      for (final Tag t in await database.syncDao.getPendingTags()) {
        try {
          final String id = await remote.upsert('tags', <String, dynamic>{
            if (t.remoteId != null) 'id': t.remoteId,
            'user_id': userId,
            'name': t.name,
          });
          await database.syncDao.markTagSynced(t.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure('tags', t.remoteId ?? '${t.id}', e);
        }
      }

      // 5. Expenses (parents: category, optional receipt).
      for (final Expense e in await database.expenseDao.getPendingSync()) {
        if (e.syncStatus == SyncStatus.pendingDelete) {
          if (await _pushDelete('expenses', e.remoteId)) {
            await database.syncDao.hardDeleteExpense(e.id);
            pushed++;
          } else {
            failed++;
          }
          continue;
        }
        final String? catRemote = await database.syncDao.categoryRemoteId(
          e.categoryId,
        );
        if (catRemote == null) {
          failed++;
          await _logFailure(
            'expenses',
            e.remoteId ?? '${e.id}',
            'category ${e.categoryId} has no remote id yet (parent unsynced)',
          );
          continue;
        }
        final int? localReceipt = e.receiptId;
        try {
          final String id = await remote.upsert('expenses', <String, dynamic>{
            if (e.remoteId != null) 'id': e.remoteId,
            'user_id': userId,
            'amount': e.amount,
            'category_id': catRemote,
            'receipt_id': localReceipt == null
                ? null
                : await database.syncDao.receiptRemoteId(localReceipt),
            'note': e.note,
            'date': e.date.toUtc().toIso8601String(),
            'is_manual': e.isManual,
            'is_recurring': e.isRecurring,
            'recurring_period': e.recurringPeriod,
          });
          await database.syncDao.markExpenseSynced(e.id, remoteId: id);
          pushed++;
        } on Object catch (err) {
          failed++;
          await _logFailure('expenses', e.remoteId ?? '${e.id}', err);
        }
      }

      // 6. Budgets (parent: optional category).
      for (final Budget b in await database.budgetDao.getPendingSync()) {
        if (b.syncStatus == SyncStatus.pendingDelete) {
          if (await _pushDelete('budgets', b.remoteId)) {
            await database.syncDao.hardDeleteBudget(b.id);
            pushed++;
          } else {
            failed++;
          }
          continue;
        }
        final int? localCat = b.categoryId;
        try {
          final String id = await remote.upsert('budgets', <String, dynamic>{
            if (b.remoteId != null) 'id': b.remoteId,
            'user_id': userId,
            'category_id': localCat == null
                ? null
                : await database.syncDao.categoryRemoteId(localCat),
            'amount': b.amount,
            'period': b.period,
            'start_date': _dateOnly(b.startDate),
            'is_active': b.isActive,
          });
          await database.syncDao.markBudgetSynced(b.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure('budgets', b.remoteId ?? '${b.id}', e);
        }
      }

      // 7. User corrections (parents: categories).
      for (final UserCorrection uc
          in await database.userCorrectionDao.getPendingSync()) {
        final String? newCatRemote = await database.syncDao.categoryRemoteId(
          uc.newCategoryId,
        );
        if (newCatRemote == null) {
          failed++;
          await _logFailure(
            'user_corrections',
            uc.remoteId ?? '${uc.id}',
            'category ${uc.newCategoryId} has no remote id (parent unsynced)',
          );
          continue;
        }
        final int? oldCat = uc.oldCategoryId;
        try {
          final String id = await remote.upsert(
            'user_corrections',
            <String, dynamic>{
              if (uc.remoteId != null) 'id': uc.remoteId,
              'user_id': userId,
              'store_name': uc.storeName,
              'old_category_id': oldCat == null
                  ? null
                  : await database.syncDao.categoryRemoteId(oldCat),
              'new_category_id': newCatRemote,
              'count': uc.count,
              'occurred_at': uc.occurredAt.toUtc().toIso8601String(),
            },
          );
          await database.syncDao.markUserCorrectionSynced(uc.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure(
            'user_corrections',
            uc.remoteId ?? '${uc.id}',
            e,
          );
        }
      }

      // 8. Taxpayer profile (no parent).
      //
      // Pushed with an explicit conflict target rather than on `id`. The row
      // is one-per-user and a second device can create its own copy offline —
      // wizard filled on the tablet before the phone's profile ever reached
      // it — so there is no shared `id` to conflict on. Without the target
      // that insert would trip the table's UNIQUE (user_id) forever.
      for (final TaxProfile tp
          in await database.taxProfileDao.getPendingSync()) {
        try {
          final String id = await remote.upsert(
            'tax_profiles',
            <String, dynamic>{
              if (tp.remoteId != null) 'id': tp.remoteId,
              'user_id': userId,
              'legal_form': tp.legalForm,
              'vat_liability': tp.vatLiability,
              'withholding_liability': tp.withholdingLiability,
              'employs_staff': tp.employsStaff,
              'bagkur_insured': tp.bagkurInsured,
              'uses_e_ledger': tp.usesELedger,
              'owns_vehicle': tp.ownsVehicle,
              'owns_real_estate': tp.ownsRealEstate,
              'created_at': tp.createdAt.toUtc().toIso8601String(),
            },
            onConflict: 'user_id',
          );
          await database.syncDao.markTaxProfileSynced(tp.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure('tax_profiles', tp.remoteId ?? '${tp.id}', e);
        }
      }

      // 9. Tax obligations (no parent — the profile they came from is not a
      // foreign key; regenerating from a changed profile rewrites the items).
      //
      // Same conflict-target reasoning as the profile: generation is
      // deterministic, so a second device holds its own copy of August's
      // return with no server id. UNIQUE (user_id, generation_key) is what
      // makes those two rows one deadline instead of two.
      for (final TaxObligation to
          in await database.taxObligationDao.getPendingSync()) {
        try {
          final String id = await remote.upsert(
            'tax_obligations',
            <String, dynamic>{
              if (to.remoteId != null) 'id': to.remoteId,
              'user_id': userId,
              'generation_key': to.generationKey,
              'kind': to.kind,
              'period_kind': to.periodKind,
              'period_start': _dateOnly(to.periodStart),
              'period_end': _dateOnly(to.periodEnd),
              'installment_index': to.installmentIndex,
              'declaration_due_date': to.declarationDueDate == null
                  ? null
                  : _dateOnly(to.declarationDueDate!),
              'payment_due_date': to.paymentDueDate == null
                  ? null
                  : _dateOnly(to.paymentDueDate!),
              'due_date_source': to.dueDateSource,
              'amount_minor': to.amountMinor,
              'amount_source': to.amountSource,
              'declared_at': to.declaredAt?.toUtc().toIso8601String(),
              'paid_at': to.paidAt?.toUtc().toIso8601String(),
              'dismissed_at': to.dismissedAt?.toUtc().toIso8601String(),
              'note': to.note,
              'title': to.title,
              'is_user_defined': to.isUserDefined,
              'created_at': to.createdAt.toUtc().toIso8601String(),
            },
            onConflict: 'user_id,generation_key',
          );
          await database.syncDao.markTaxObligationSynced(to.id, remoteId: id);
          pushed++;
        } on Object catch (e) {
          failed++;
          await _logFailure('tax_obligations', to.remoteId ?? '${to.id}', e);
        }
      }

      return Right<Failure, SyncReport>(
        SyncReport(pushed: pushed, failed: failed),
      );
    } on Object catch (e, st) {
      return Left<Failure, SyncReport>(SupabaseErrorMapper.map(e, st));
    }
  }

  /// Returns true when the remote delete succeeded (or the row never had a
  /// remote copy and only needs local cleanup).
  Future<bool> _pushDelete(String table, String? remoteId) async {
    try {
      if (remoteId != null) await remote.deleteById(table, remoteId);
      return true;
    } on Object catch (e) {
      await _logFailure(table, remoteId ?? '?', e);
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Pull (Supabase → Drift), last-write-wins by updated_at
  // -----------------------------------------------------------------------

  @override
  Future<Either<Failure, SyncReport>> pull() async {
    try {
      // No session → RLS scopes every query to nobody, so there is nothing to
      // pull. Crucially, do NOT advance the watermark below: a pre-sign-in run
      // (startup timer / connectivity) would otherwise stamp lastSyncAt=now,
      // turning the real pull right after sign-in into an incremental
      // `updated_at > now` fetch that returns zero rows — an empty dashboard on
      // fresh install / re-login. Mirrors the guard in push().
      if (remote.currentUserId == null) {
        return const Right<Failure, SyncReport>(SyncReport());
      }
      final DateTime? since = await database.syncDao.getLastSyncAt();
      int pulled = 0;
      int conflicts = 0;
      int deferred = 0;

      // Categories.
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'categories',
        since,
      )) {
        final bool written = await database.syncDao.applyCategoryFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          name: row['name'] as String,
          icon: row['icon'] as String,
          color: (row['color'] as num).toInt(),
          isCustom: row['is_custom'] as bool,
          sortOrder: (row['sort_order'] as num).toInt(),
          updatedAt: DateTime.parse(row['updated_at'] as String),
          userId: row['user_id'] as String?,
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('categories', row['id'] as String);
        }
      }

      // Receipts.
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'receipts',
        since,
      )) {
        final Object? warranty = row['warranty_end_date'];
        final bool written = await database.syncDao.applyReceiptFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          date: _parseRemoteDate(row['date'] as String),
          total: (row['total'] as num).toInt(),
          currency: row['currency'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          updatedAt: DateTime.parse(row['updated_at'] as String),
          userId: row['user_id'] as String?,
          storeName: row['store_name'] as String?,
          imagePath: row['image_path'] as String?,
          storageObjectPath: row['storage_object_path'] as String?,
          rawOcrText: row['raw_ocr_text'] as String?,
          confidenceScore: (row['confidence_score'] as num?)?.toDouble(),
          warrantyEndDate: warranty == null
              ? null
              : _parseRemoteDate(warranty as String),
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('receipts', row['id'] as String);
        }
      }

      // Receipt items (parent: receipts already pulled above; optional cat).
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'receipt_items',
        since,
      )) {
        final int? localReceipt = await database.syncDao
            .localReceiptIdForRemote(row['receipt_id'] as String?);
        if (localReceipt == null) {
          // The parent receipt is not here yet. Hold the row instead of
          // dropping it: the watermark below moves past it either way, so a
          // bare `continue` meant this device would never ask for it again.
          deferred++;
          await _deferRow(
            table: 'receipt_items',
            row: row,
            missingParentTable: 'receipts',
            missingParentRemoteId: row['receipt_id'] as String?,
          );
          continue;
        }
        final int? localCat = await database.syncDao.localCategoryIdForRemote(
          row['category_id'] as String?,
        );
        final bool written = await database.syncDao.applyReceiptItemFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          receiptId: localReceipt,
          name: row['name'] as String,
          quantity: (row['quantity'] as num).toDouble(),
          unitPrice: (row['unit_price'] as num).toInt(),
          totalPrice: (row['total_price'] as num).toInt(),
          updatedAt: DateTime.parse(row['updated_at'] as String),
          userId: row['user_id'] as String?,
          categoryId: localCat,
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('receipt_items', row['id'] as String);
        }
      }

      // Tags (no parent).
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'tags',
        since,
      )) {
        final bool written = await database.syncDao.applyTagFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          name: row['name'] as String,
          updatedAt: DateTime.parse(row['updated_at'] as String),
          userId: row['user_id'] as String?,
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('tags', row['id'] as String);
        }
      }

      // Expenses (resolve remote FK UUIDs to local ids).
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'expenses',
        since,
      )) {
        final int? localCat = await database.syncDao.localCategoryIdForRemote(
          row['category_id'] as String?,
        );
        if (localCat == null) {
          deferred++;
          await _deferRow(
            table: 'expenses',
            row: row,
            missingParentTable: 'categories',
            missingParentRemoteId: row['category_id'] as String?,
          );
          continue;
        }
        final int? localReceipt = await database.syncDao
            .localReceiptIdForRemote(row['receipt_id'] as String?);
        final bool written = await database.syncDao.applyExpenseFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          amount: (row['amount'] as num).toInt(),
          categoryId: localCat,
          date: DateTime.parse(row['date'] as String),
          createdAt: DateTime.parse(row['created_at'] as String),
          updatedAt: DateTime.parse(row['updated_at'] as String),
          userId: row['user_id'] as String?,
          receiptId: localReceipt,
          note: row['note'] as String?,
          isManual: row['is_manual'] as bool,
          isRecurring: row['is_recurring'] as bool,
          recurringPeriod: row['recurring_period'] as String?,
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('expenses', row['id'] as String);
        }
      }

      // Budgets (resolve optional category FK).
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'budgets',
        since,
      )) {
        final int? localCat = await database.syncDao.localCategoryIdForRemote(
          row['category_id'] as String?,
        );
        final bool written = await database.syncDao.applyBudgetFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          amount: (row['amount'] as num).toInt(),
          period: row['period'] as String,
          startDate: _parseRemoteDate(row['start_date'] as String),
          isActive: row['is_active'] as bool,
          updatedAt: DateTime.parse(row['updated_at'] as String),
          userId: row['user_id'] as String?,
          categoryId: localCat,
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('budgets', row['id'] as String);
        }
      }

      // User corrections (parent: categories — new required, old optional).
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'user_corrections',
        since,
      )) {
        final int? localNewCat = await database.syncDao
            .localCategoryIdForRemote(row['new_category_id'] as String?);
        if (localNewCat == null) {
          deferred++;
          await _deferRow(
            table: 'user_corrections',
            row: row,
            missingParentTable: 'categories',
            missingParentRemoteId: row['new_category_id'] as String?,
          );
          continue;
        }
        final int? localOldCat = await database.syncDao
            .localCategoryIdForRemote(row['old_category_id'] as String?);
        final bool written = await database.syncDao
            .applyUserCorrectionFromRemote(
              remoteId: row['id'] as String,
              remotePayload: row,
              storeName: row['store_name'] as String,
              newCategoryId: localNewCat,
              count: (row['count'] as num).toInt(),
              occurredAt: DateTime.parse(row['occurred_at'] as String),
              updatedAt: DateTime.parse(row['updated_at'] as String),
              userId: row['user_id'] as String?,
              oldCategoryId: localOldCat,
            );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('user_corrections', row['id'] as String);
        }
      }

      // Taxpayer profile (no parent).
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'tax_profiles',
        since,
      )) {
        final bool written = await database.syncDao.applyTaxProfileFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          legalForm: row['legal_form'] as String,
          vatLiability: row['vat_liability'] as String,
          withholdingLiability: row['withholding_liability'] as String,
          employsStaff: row['employs_staff'] as String,
          bagkurInsured: row['bagkur_insured'] as String,
          usesELedger: row['uses_e_ledger'] as String,
          ownsVehicle: row['owns_vehicle'] as String,
          ownsRealEstate: row['owns_real_estate'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          updatedAt: DateTime.parse(row['updated_at'] as String),
          userId: row['user_id'] as String?,
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('tax_profiles', row['id'] as String);
        }
      }

      // Tax obligations (no parent).
      for (final Map<String, dynamic> row in await remote.fetchSince(
        'tax_obligations',
        since,
      )) {
        final String? declarationDue = row['declaration_due_date'] as String?;
        final String? paymentDue = row['payment_due_date'] as String?;
        final String? declaredAt = row['declared_at'] as String?;
        final String? paidAt = row['paid_at'] as String?;
        final String? dismissedAt = row['dismissed_at'] as String?;
        final bool written =
            await database.syncDao.applyTaxObligationFromRemote(
          remoteId: row['id'] as String,
          remotePayload: row,
          generationKey: row['generation_key'] as String,
          kind: row['kind'] as String,
          periodKind: row['period_kind'] as String,
          periodStart: _parseRemoteDate(row['period_start'] as String),
          periodEnd: _parseRemoteDate(row['period_end'] as String),
          installmentIndex: (row['installment_index'] as num).toInt(),
          dueDateSource: row['due_date_source'] as String,
          amountSource: row['amount_source'] as String,
          isUserDefined: row['is_user_defined'] as bool,
          createdAt: DateTime.parse(row['created_at'] as String),
          updatedAt: DateTime.parse(row['updated_at'] as String),
          declarationDueDate: declarationDue == null
              ? null
              : _parseRemoteDate(declarationDue),
          paymentDueDate:
              paymentDue == null ? null : _parseRemoteDate(paymentDue),
          amountMinor: (row['amount_minor'] as num?)?.toInt(),
          declaredAt:
              declaredAt == null ? null : DateTime.parse(declaredAt).toUtc(),
          paidAt: paidAt == null ? null : DateTime.parse(paidAt).toUtc(),
          dismissedAt:
              dismissedAt == null ? null : DateTime.parse(dismissedAt).toUtc(),
          note: row['note'] as String?,
          title: row['title'] as String?,
          userId: row['user_id'] as String?,
        );
        if (written) {
          pulled++;
        } else {
          conflicts++;
          await _logConflict('tax_obligations', row['id'] as String);
        }
      }

      await database.syncDao.setLastSyncAt(DateTime.now().toUtc());
      return Right<Failure, SyncReport>(
        SyncReport(pulled: pulled, conflicts: conflicts, deferred: deferred),
      );
    } on Object catch (e, st) {
      return Left<Failure, SyncReport>(SupabaseErrorMapper.map(e, st));
    }
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  Future<void> _logFailure(String table, String recordId, Object error) {
    return database.syncLogDao.log(
      tableName: table,
      recordId: recordId,
      operation: SyncOperation.update,
      success: false,
      errorMessage: error.toString(),
    );
  }

  /// Holds a pulled row whose parent has not reached this device yet.
  ///
  /// The parent lookup fails before any `apply*FromRemote` runs, so unlike a
  /// conflict there is no DAO decision point to hang this on — the pull loop
  /// has to record it itself. Both the row and the identity of the parent it
  /// is waiting for are kept, so 1.4.0 can replay it once the parent lands.
  Future<void> _deferRow({
    required String table,
    required Map<String, dynamic> row,
    required String missingParentTable,
    String? missingParentRemoteId,
  }) async {
    final String recordId = row['id'] as String;
    await database.syncDao.recordDeferredRow(
      tableName: table,
      remoteId: recordId,
      remotePayload: row,
      remoteUpdatedAt: DateTime.parse(row['updated_at'] as String),
      missingParentTable: missingParentTable,
      missingParentRemoteId: missingParentRemoteId,
      userId: row['user_id'] as String?,
    );
    await database.syncLogDao.log(
      tableName: table,
      recordId: recordId,
      operation: SyncOperation.deferredMissingParent,
      success: true,
    );
  }

  /// Records *that* a conflict happened. *What* was discarded is written by
  /// the DAO itself, at the point of the decision — see
  /// [SyncDao.recordConflictPayload].
  Future<void> _logConflict(String table, String recordId) {
    return database.syncLogDao.log(
      tableName: table,
      recordId: recordId,
      operation: SyncOperation.conflictResolved,
      success: true,
    );
  }

  /// Formats a [DateTime] as a bare `yyyy-MM-dd` for Postgres `date` columns.
  String _dateOnly(DateTime d) => d.toUtc().toIso8601String().split('T').first;

  /// Parses a remote value that may be a bare `date` (`yyyy-MM-dd`) or a full
  /// timestamp, always yielding UTC. Bare dates are pinned to UTC midnight so
  /// the day never shifts across the device timezone.
  DateTime _parseRemoteDate(String value) {
    final String normalized = value.length == 10 ? '${value}T00:00:00Z' : value;
    return DateTime.parse(normalized).toUtc();
  }
}
