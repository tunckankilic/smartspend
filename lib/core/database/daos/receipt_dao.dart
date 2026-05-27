import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'receipt_dao.g.dart';

/// CRUD + sync-aware operations for [Receipts] and child [ReceiptItems].
///
/// Every mutating method here is responsible for stamping `updatedAt` and
/// flipping `syncStatus` to the appropriate `pending_*` value so the sync
/// engine can find dirty rows later via [getPendingSync].
@DriftAccessor(tables: <Type>[Receipts, ReceiptItems])
class ReceiptDao extends DatabaseAccessor<AppDatabase> with _$ReceiptDaoMixin {
  ReceiptDao(super.db);

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  /// Insert a receipt and mark it for upstream creation.
  ///
  /// Pass a partially populated [ReceiptsCompanion]; `createdAt`,
  /// `updatedAt`, and `syncStatus` are overwritten here.
  Future<int> insertReceipt(ReceiptsCompanion entry) {
    final DateTime now = DateTime.now().toUtc();
    return into(receipts).insert(
      entry.copyWith(
        createdAt: Value<DateTime>(now),
        updatedAt: Value<DateTime>(now),
        syncStatus: const Value<String>(SyncStatus.pendingCreate),
      ),
    );
  }

  /// Insert a single line item. Stamps `updatedAt` and `pending_create`.
  Future<int> insertItem(ReceiptItemsCompanion entry) {
    return into(receiptItems).insert(
      entry.copyWith(
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        syncStatus: const Value<String>(SyncStatus.pendingCreate),
      ),
    );
  }

  /// All non-deleted items belonging to [receiptId].
  Future<List<ReceiptItem>> getItems(int receiptId) {
    return (select(receiptItems)
          ..where(
            ($ReceiptItemsTable t) =>
                t.receiptId.equals(receiptId) &
                t.syncStatus.equals(SyncStatus.pendingDelete).not(),
          ))
        .get();
  }

  /// Update a receipt by its local [id]. Returns the number of affected rows.
  Future<int> updateReceipt(int id, ReceiptsCompanion patch) {
    return (update(receipts)..where(($ReceiptsTable t) => t.id.equals(id)))
        .write(
      patch.copyWith(
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        syncStatus: const Value<String>(SyncStatus.pendingUpdate),
      ),
    );
  }

  /// Soft-delete — the row stays until the sync engine confirms remote
  /// deletion, then `hardDelete` removes it.
  Future<int> softDeleteReceipt(int id) {
    return (update(receipts)..where(($ReceiptsTable t) => t.id.equals(id)))
        .write(
      ReceiptsCompanion(
        syncStatus: const Value<String>(SyncStatus.pendingDelete),
        updatedAt: Value<DateTime>(DateTime.now().toUtc()),
      ),
    );
  }

  /// Physically delete a row — only called by `SyncService` after Supabase
  /// confirms the remote delete.
  Future<int> hardDeleteReceipt(int id) {
    return (delete(receipts)..where(($ReceiptsTable t) => t.id.equals(id)))
        .go();
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  Future<Receipt?> getById(int id) {
    return (select(receipts)..where(($ReceiptsTable t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// All non-deleted receipts. Optionally bounded by [from] / [to] inclusive.
  Future<List<Receipt>> getAll({DateTime? from, DateTime? to}) {
    final SimpleSelectStatement<$ReceiptsTable, Receipt> q = select(receipts)
      ..where(
        ($ReceiptsTable t) =>
            t.syncStatus.equals(SyncStatus.pendingDelete).not(),
      )
      ..orderBy(<OrderClauseGenerator<$ReceiptsTable>>[
        ($ReceiptsTable t) =>
            OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      ]);
    if (from != null) {
      q.where(($ReceiptsTable t) => t.date.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      q.where(($ReceiptsTable t) => t.date.isSmallerOrEqualValue(to));
    }
    return q.get();
  }

  /// Case-insensitive substring search against `store_name`.
  Future<List<Receipt>> searchByStore(String query) {
    final String like = '%${query.toLowerCase()}%';
    return (select(receipts)
          ..where(
            ($ReceiptsTable t) => t.storeName.lower().like(like),
          ))
        .get();
  }

  /// Rows the sync engine still needs to push.
  Future<List<Receipt>> getPendingSync() {
    return (select(receipts)
          ..where(
            ($ReceiptsTable t) => t.syncStatus.isIn(SyncStatus.pending),
          ))
        .get();
  }
}
