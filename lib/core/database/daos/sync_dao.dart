import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'sync_dao.g.dart';

/// Local-side persistence primitives the `SyncService` engine needs.
///
/// Centralises the generic "stamp this local row as synced", "look up a
/// local row by its Supabase `remoteId`", and "apply a freshly pulled
/// remote row" operations across every syncable table. Keeping them in one
/// accessor means the sync engine owns its own SQL surface instead of
/// spreading sync concerns across the per-feature DAOs.
///
/// The `last_sync_at` watermark lives in [UserSettings] as a key/value
/// pair (ISO-8601 UTC string) so a fresh install pulls the full history.
@DriftAccessor(
  tables: <Type>[
    Categories,
    Receipts,
    ReceiptItems,
    Expenses,
    Budgets,
    Tags,
    UserCorrections,
    UserSettings,
  ],
)
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  /// UserSettings key holding the last successful pull watermark.
  static const String kLastSyncAtKey = 'last_sync_at';

  // ---------------------------------------------------------------------
  // Sync watermark
  // ---------------------------------------------------------------------

  /// Reads the last successful pull time, or `null` if the device has never
  /// synced (treat as "pull everything").
  Future<DateTime?> getLastSyncAt() async {
    final UserSetting? row =
        await (select(userSettings)
              ..where(($UserSettingsTable t) => t.key.equals(kLastSyncAtKey))
              ..limit(1))
            .getSingleOrNull();
    final String? raw = row?.value;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// Persists [at] (stored as UTC ISO-8601) as the new pull watermark.
  Future<void> setLastSyncAt(DateTime at) {
    return into(userSettings).insertOnConflictUpdate(
      UserSettingsCompanion.insert(
        key: kLastSyncAtKey,
        value: at.toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Mark-synced (push success)
  // ---------------------------------------------------------------------

  Future<void> markCategorySynced(int id, {String? remoteId}) {
    return (update(
      categories,
    )..where(($CategoriesTable t) => t.id.equals(id))).write(
      CategoriesCompanion(
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
        syncStatus: const Value<String>(SyncStatus.synced),
      ),
    );
  }

  Future<void> markReceiptSynced(int id, {String? remoteId}) {
    return (update(
      receipts,
    )..where(($ReceiptsTable t) => t.id.equals(id))).write(
      ReceiptsCompanion(
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
        syncStatus: const Value<String>(SyncStatus.synced),
      ),
    );
  }

  Future<void> markReceiptItemSynced(int id, {String? remoteId}) {
    return (update(
      receiptItems,
    )..where(($ReceiptItemsTable t) => t.id.equals(id))).write(
      ReceiptItemsCompanion(
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
        syncStatus: const Value<String>(SyncStatus.synced),
      ),
    );
  }

  Future<void> markExpenseSynced(int id, {String? remoteId}) {
    return (update(
      expenses,
    )..where(($ExpensesTable t) => t.id.equals(id))).write(
      ExpensesCompanion(
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
        syncStatus: const Value<String>(SyncStatus.synced),
      ),
    );
  }

  Future<void> markBudgetSynced(int id, {String? remoteId}) {
    return (update(budgets)..where(($BudgetsTable t) => t.id.equals(id))).write(
      BudgetsCompanion(
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
        syncStatus: const Value<String>(SyncStatus.synced),
      ),
    );
  }

  Future<void> markTagSynced(int id, {String? remoteId}) {
    return (update(tags)..where(($TagsTable t) => t.id.equals(id))).write(
      TagsCompanion(
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
        syncStatus: const Value<String>(SyncStatus.synced),
      ),
    );
  }

  Future<void> markUserCorrectionSynced(int id, {String? remoteId}) {
    return (update(
      userCorrections,
    )..where(($UserCorrectionsTable t) => t.id.equals(id))).write(
      UserCorrectionsCompanion(
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
        syncStatus: const Value<String>(SyncStatus.synced),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Pending-row queries for tables whose feature DAO lacks getPendingSync.
  // ---------------------------------------------------------------------

  /// Receipt line items awaiting push (`pending_*`). Their feature DAO has
  /// no `getPendingSync`, so the sync engine reads them here.
  Future<List<ReceiptItem>> getPendingReceiptItems() {
    return (select(receiptItems)..where(
          ($ReceiptItemsTable t) => t.syncStatus.isIn(SyncStatus.pending),
        ))
        .get();
  }

  /// Tags awaiting push (`pending_*`).
  Future<List<Tag>> getPendingTags() {
    return (select(
      tags,
    )..where(($TagsTable t) => t.syncStatus.isIn(SyncStatus.pending))).get();
  }

  // ---------------------------------------------------------------------
  // FK remap helpers — resolve a parent's remote UUID from its local id.
  // ---------------------------------------------------------------------

  Future<String?> categoryRemoteId(int localId) async {
    final Category? row =
        await (select(categories)
              ..where(($CategoriesTable t) => t.id.equals(localId))
              ..limit(1))
            .getSingleOrNull();
    return row?.remoteId;
  }

  Future<String?> receiptRemoteId(int localId) async {
    final Receipt? row =
        await (select(receipts)
              ..where(($ReceiptsTable t) => t.id.equals(localId))
              ..limit(1))
            .getSingleOrNull();
    return row?.remoteId;
  }

  // ---------------------------------------------------------------------
  // Find-by-remoteId (pull dedupe) + local id resolution
  // ---------------------------------------------------------------------

  Future<Category?> findCategoryByRemoteId(String remoteId) {
    return (select(categories)
          ..where(($CategoriesTable t) => t.remoteId.equals(remoteId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<Receipt?> findReceiptByRemoteId(String remoteId) {
    return (select(receipts)
          ..where(($ReceiptsTable t) => t.remoteId.equals(remoteId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<Expense?> findExpenseByRemoteId(String remoteId) {
    return (select(expenses)
          ..where(($ExpensesTable t) => t.remoteId.equals(remoteId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<Budget?> findBudgetByRemoteId(String remoteId) {
    return (select(budgets)
          ..where(($BudgetsTable t) => t.remoteId.equals(remoteId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int?> localCategoryIdForRemote(String? remoteId) async {
    if (remoteId == null) return null;
    final Category? row = await findCategoryByRemoteId(remoteId);
    return row?.id;
  }

  Future<int?> localReceiptIdForRemote(String? remoteId) async {
    if (remoteId == null) return null;
    final Receipt? row = await findReceiptByRemoteId(remoteId);
    return row?.id;
  }

  // ---------------------------------------------------------------------
  // Hard delete (after remote delete confirmed)
  // ---------------------------------------------------------------------

  Future<void> hardDeleteReceipt(int id) =>
      (delete(receipts)..where(($ReceiptsTable t) => t.id.equals(id))).go();

  Future<void> hardDeleteExpense(int id) =>
      (delete(expenses)..where(($ExpensesTable t) => t.id.equals(id))).go();

  Future<void> hardDeleteBudget(int id) =>
      (delete(budgets)..where(($BudgetsTable t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------------
  // Pull apply — insert-or-(last-write-wins)-update by remoteId.
  // Returns true when the row was written, false when skipped because the
  // local copy is newer (last-write-wins keeps local).
  // ---------------------------------------------------------------------

  Future<bool> applyCategoryFromRemote({
    required String remoteId,
    required String name,
    required String icon,
    required int color,
    required bool isCustom,
    required int sortOrder,
    required DateTime updatedAt,
    String? userId,
  }) async {
    final Category? existing = await findCategoryByRemoteId(remoteId);
    final CategoriesCompanion values = CategoriesCompanion(
      remoteId: Value<String?>(remoteId),
      userId: Value<String?>(userId),
      name: Value<String>(name),
      icon: Value<String>(icon),
      color: Value<int>(color),
      isCustom: Value<bool>(isCustom),
      sortOrder: Value<int>(sortOrder),
      updatedAt: Value<DateTime>(updatedAt.toUtc()),
      syncStatus: const Value<String>(SyncStatus.synced),
    );
    if (existing == null) {
      await into(categories).insert(values);
      return true;
    }
    if (!updatedAt.toUtc().isAfter(existing.updatedAt.toUtc())) return false;
    await (update(
      categories,
    )..where(($CategoriesTable t) => t.id.equals(existing.id))).write(values);
    return true;
  }

  Future<bool> applyReceiptFromRemote({
    required String remoteId,
    required DateTime date,
    required int total,
    required String currency,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? userId,
    String? storeName,
    String? imagePath,
    String? storageObjectPath,
    String? rawOcrText,
    double? confidenceScore,
    DateTime? warrantyEndDate,
  }) async {
    final Receipt? existing = await findReceiptByRemoteId(remoteId);
    final ReceiptsCompanion values = ReceiptsCompanion(
      remoteId: Value<String?>(remoteId),
      userId: Value<String?>(userId),
      storeName: Value<String?>(storeName),
      date: Value<DateTime>(date.toUtc()),
      total: Value<int>(total),
      currency: Value<String>(currency),
      imagePath: Value<String?>(imagePath),
      storageObjectPath: Value<String?>(storageObjectPath),
      rawOcrText: Value<String?>(rawOcrText),
      confidenceScore: Value<double?>(confidenceScore),
      warrantyEndDate: Value<DateTime?>(warrantyEndDate?.toUtc()),
      createdAt: Value<DateTime>(createdAt.toUtc()),
      updatedAt: Value<DateTime>(updatedAt.toUtc()),
      syncStatus: const Value<String>(SyncStatus.synced),
    );
    if (existing == null) {
      await into(receipts).insert(values);
      return true;
    }
    if (!updatedAt.toUtc().isAfter(existing.updatedAt.toUtc())) return false;
    await (update(
      receipts,
    )..where(($ReceiptsTable t) => t.id.equals(existing.id))).write(values);
    return true;
  }

  Future<bool> applyExpenseFromRemote({
    required String remoteId,
    required int amount,
    required int categoryId,
    required DateTime date,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? userId,
    int? receiptId,
    String? note,
    bool isManual = true,
    bool isRecurring = false,
    String? recurringPeriod,
  }) async {
    final Expense? existing = await findExpenseByRemoteId(remoteId);
    final ExpensesCompanion values = ExpensesCompanion(
      remoteId: Value<String?>(remoteId),
      userId: Value<String?>(userId),
      amount: Value<int>(amount),
      categoryId: Value<int>(categoryId),
      receiptId: Value<int?>(receiptId),
      note: Value<String?>(note),
      date: Value<DateTime>(date.toUtc()),
      isManual: Value<bool>(isManual),
      isRecurring: Value<bool>(isRecurring),
      recurringPeriod: Value<String?>(recurringPeriod),
      createdAt: Value<DateTime>(createdAt.toUtc()),
      updatedAt: Value<DateTime>(updatedAt.toUtc()),
      syncStatus: const Value<String>(SyncStatus.synced),
    );
    if (existing == null) {
      await into(expenses).insert(values);
      return true;
    }
    if (!updatedAt.toUtc().isAfter(existing.updatedAt.toUtc())) return false;
    await (update(
      expenses,
    )..where(($ExpensesTable t) => t.id.equals(existing.id))).write(values);
    return true;
  }

  Future<bool> applyBudgetFromRemote({
    required String remoteId,
    required int amount,
    required String period,
    required DateTime startDate,
    required bool isActive,
    required DateTime updatedAt,
    String? userId,
    int? categoryId,
  }) async {
    final Budget? existing = await findBudgetByRemoteId(remoteId);
    final BudgetsCompanion values = BudgetsCompanion(
      remoteId: Value<String?>(remoteId),
      userId: Value<String?>(userId),
      categoryId: Value<int?>(categoryId),
      amount: Value<int>(amount),
      period: Value<String>(period),
      startDate: Value<DateTime>(startDate.toUtc()),
      isActive: Value<bool>(isActive),
      updatedAt: Value<DateTime>(updatedAt.toUtc()),
      syncStatus: const Value<String>(SyncStatus.synced),
    );
    if (existing == null) {
      await into(budgets).insert(values);
      return true;
    }
    if (!updatedAt.toUtc().isAfter(existing.updatedAt.toUtc())) return false;
    await (update(
      budgets,
    )..where(($BudgetsTable t) => t.id.equals(existing.id))).write(values);
    return true;
  }
}
