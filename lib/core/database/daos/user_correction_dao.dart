import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'user_correction_dao.g.dart';

/// Drift access layer for `user_corrections` (introduced in schema v2).
///
/// The table is a learning signal for [HybridCategorizationEngine]: each
/// time the user overrides a suggested category for a store, we either
/// insert a new row or bump the `count` on the matching one. The engine
/// then prefers the highest-count row before consulting the keyword DB.
@DriftAccessor(tables: <Type>[UserCorrections])
class UserCorrectionDao extends DatabaseAccessor<AppDatabase>
    with _$UserCorrectionDaoMixin {
  UserCorrectionDao(super.db);

  /// Idempotently records a correction.
  ///
  /// If a row already exists for `(storeName lower-cased, newCategoryId)` we
  /// increment its `count` and refresh `occurredAt` so the most recent
  /// override floats to the top. Otherwise a new row is inserted.
  ///
  /// Match is case-insensitive on `store_name` so "Migros" and "MIGROS"
  /// share a single learning row.
  Future<void> upsertCorrection({
    required String storeName,
    required int? oldCategoryId,
    required int newCategoryId,
    required DateTime occurredAt,
    String? userId,
  }) async {
    final String normalized = storeName.trim();
    if (normalized.isEmpty) {
      return;
    }
    final DateTime now = DateTime.now().toUtc();
    final UserCorrection? existing = await (select(userCorrections)
          ..where(
            ($UserCorrectionsTable t) =>
                t.storeName.lower().equals(normalized.toLowerCase()) &
                t.newCategoryId.equals(newCategoryId),
          )
          ..limit(1))
        .getSingleOrNull();

    if (existing == null) {
      await into(userCorrections).insert(
        UserCorrectionsCompanion.insert(
          userId: Value<String?>(userId),
          storeName: normalized,
          oldCategoryId: Value<int?>(oldCategoryId),
          newCategoryId: newCategoryId,
          occurredAt: occurredAt,
          updatedAt: now,
          syncStatus: const Value<String>(SyncStatus.pendingCreate),
        ),
      );
      return;
    }

    await (update(userCorrections)
          ..where(($UserCorrectionsTable t) => t.id.equals(existing.id)))
        .write(
      UserCorrectionsCompanion(
        count: Value<int>(existing.count + 1),
        occurredAt: Value<DateTime>(occurredAt),
        updatedAt: Value<DateTime>(now),
        syncStatus: const Value<String>(SyncStatus.pendingUpdate),
      ),
    );
  }

  /// Returns the highest-count correction for a given store name, or null
  /// when the user has never overridden anything for that store.
  ///
  /// Used by the hybrid engine as the first lookup layer before keyword
  /// matching kicks in.
  Future<UserCorrection?> getTopCorrectionForStore(String storeName) {
    final String normalized = storeName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return Future<UserCorrection?>.value();
    }
    return (select(userCorrections)
          ..where(
            ($UserCorrectionsTable t) =>
                t.storeName.lower().equals(normalized),
          )
          ..orderBy(<OrderClauseGenerator<$UserCorrectionsTable>>[
            ($UserCorrectionsTable t) => OrderingTerm.desc(t.count),
            ($UserCorrectionsTable t) => OrderingTerm.desc(t.occurredAt),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// All corrections, ordered most recent first. Useful for debug pages and
  /// the Sprint 8 sync pump.
  Stream<List<UserCorrection>> watchAll() {
    return (select(userCorrections)
          ..orderBy(<OrderClauseGenerator<$UserCorrectionsTable>>[
            ($UserCorrectionsTable t) => OrderingTerm.desc(t.occurredAt),
          ]))
        .watch();
  }

  Future<List<UserCorrection>> getPendingSync() {
    return (select(userCorrections)
          ..where(
            ($UserCorrectionsTable t) => t.syncStatus.isIn(SyncStatus.pending),
          ))
        .get();
  }
}
