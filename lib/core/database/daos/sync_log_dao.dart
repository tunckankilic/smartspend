import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/tables.dart';

part 'sync_log_dao.g.dart';

/// Audit log for sync attempts. Used by `SyncService` (Sprint 8) and the
/// dev-only "sync status" debug screen.
///
/// The DAO surface uses `tableName` as the public parameter name even
/// though the Drift getter is `logTableName` — see [SyncLog] for why.
@DriftAccessor(tables: <Type>[SyncLog])
class SyncLogDao extends DatabaseAccessor<AppDatabase>
    with _$SyncLogDaoMixin {
  SyncLogDao(super.db);

  Future<int> log({
    required String tableName,
    required String recordId,
    required String operation,
    required bool success,
    String? userId,
    String? errorMessage,
  }) {
    return into(syncLog).insert(
      SyncLogCompanion.insert(
        logTableName: tableName,
        recordId: recordId,
        operation: operation,
        attemptedAt: DateTime.now().toUtc(),
        success: success,
        userId: Value<String?>(userId),
        errorMessage: Value<String?>(errorMessage),
      ),
    );
  }

  Future<List<SyncLogData>> recent({int limit = 100}) {
    return (select(syncLog)
          ..orderBy(<OrderClauseGenerator<$SyncLogTable>>[
            ($SyncLogTable t) => OrderingTerm(
                  expression: t.attemptedAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .get();
  }

  Future<List<SyncLogData>> failures({int limit = 100}) {
    return (select(syncLog)
          ..where(($SyncLogTable t) => t.success.equals(false))
          ..orderBy(<OrderClauseGenerator<$SyncLogTable>>[
            ($SyncLogTable t) => OrderingTerm(
                  expression: t.attemptedAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .get();
  }

  Future<int> clear() => delete(syncLog).go();
}
