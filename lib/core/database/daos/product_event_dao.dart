import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'product_event_dao.g.dart';

/// Accessor for [ProductEventCounters] — the device-local half of product
/// telemetry (1.3.0, Block 3).
///
/// Two operations carry the correctness of the whole feature:
///
/// [increment] is additive at the SQL level (`ON CONFLICT … DO UPDATE SET
/// count = count + n`) rather than read-modify-write in Dart. Telemetry is
/// recorded from UI callbacks that can overlap; a Dart-side read-then-write
/// would drop increments under concurrency, which is precisely the class of
/// silent loss this release exists to stop.
///
/// [markUploaded] is a compare-and-set, not a blind update. Between reading a
/// counter and the upload completing, the user can trigger the same event
/// again — and that increment must survive. Stamping the row `synced`
/// unconditionally would swallow it until the *next* increment happened to
/// push the row pending again. Matching on the exact value that was uploaded
/// means a counter that moved during the upload simply stays pending and goes
/// out with the following flush.
@DriftAccessor(tables: <Type>[ProductEventCounters])
class ProductEventDao extends DatabaseAccessor<AppDatabase>
    with _$ProductEventDaoMixin {
  ProductEventDao(super.db);

  /// Adds [by] to the counter for ([eventKey], [dimension], [day]), creating
  /// the row if this is the day's first occurrence.
  ///
  /// [day] is a UTC `YYYY-MM-DD` label. [dimension] is `''` for events with no
  /// categorical breakdown.
  Future<void> increment({
    required String eventKey,
    required String day,
    String dimension = '',
    int by = 1,
    DateTime? now,
  }) {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    return into(productEventCounters).insert(
      ProductEventCountersCompanion.insert(
        eventKey: eventKey,
        dimension: Value<String>(dimension),
        day: day,
        count: Value<int>(by),
        updatedAt: stamp,
      ),
      onConflict: DoUpdate(
        ($ProductEventCountersTable old) =>
            ProductEventCountersCompanion.custom(
          count: old.count + Variable<int>(by),
          updatedAt: Variable<DateTime>(stamp),
          syncStatus: const Variable<String>(SyncStatus.pendingUpdate),
        ),
        target: <Column<Object>>[
          productEventCounters.eventKey,
          productEventCounters.dimension,
          productEventCounters.day,
        ],
      ),
    );
  }

  /// Counters with unsent changes, oldest day first.
  Future<List<ProductEventCounter>> getPendingSync() {
    return (select(productEventCounters)
          ..where(($ProductEventCountersTable t) =>
              t.syncStatus.isIn(SyncStatus.pending))
          ..orderBy(<OrderClauseGenerator<$ProductEventCountersTable>>[
            ($ProductEventCountersTable t) => OrderingTerm(expression: t.day),
          ]))
        .get();
  }

  /// Marks [id] synced **only if** its count is still [uploadedCount].
  ///
  /// Returns `true` when the row was stamped, `false` when it had moved on and
  /// was deliberately left pending. See the class doc for why this is a
  /// compare-and-set.
  Future<bool> markUploaded({
    required int id,
    required int uploadedCount,
    String? remoteId,
  }) async {
    final int rows = await (update(productEventCounters)
          ..where(($ProductEventCountersTable t) =>
              t.id.equals(id) & t.count.equals(uploadedCount)))
        .write(
      ProductEventCountersCompanion(
        syncStatus: const Value<String>(SyncStatus.synced),
        remoteId: remoteId == null
            ? const Value<String?>.absent()
            : Value<String?>(remoteId),
      ),
    );
    return rows > 0;
  }

  /// Test/debug read of a single counter.
  Future<ProductEventCounter?> find({
    required String eventKey,
    required String day,
    String dimension = '',
  }) {
    return (select(productEventCounters)
          ..where(($ProductEventCountersTable t) =>
              t.eventKey.equals(eventKey) &
              t.dimension.equals(dimension) &
              t.day.equals(day))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<ProductEventCounter>> getAll() =>
      select(productEventCounters).get();

  /// Deletes uploaded counters for days strictly before [day].
  ///
  /// Safe because a counter's day is always "today at the moment of
  /// recording": a row for a past day can never receive another increment, so
  /// once it is `synced` it is dead weight. The caller keeps a margin of a few
  /// days anyway, against clock skew and the UTC-midnight boundary.
  ///
  /// Deleting is not merely tidiness. Data minimisation is a KVKK obligation,
  /// and a counter that has already reached the server has no reason to keep
  /// sitting on the device.
  ///
  /// ⚠️ Never widen this to include the current day. Re-creating a day's row
  /// after upload would restart its count at 1, and since uploads write the
  /// ABSOLUTE value, the next flush would overwrite the server's higher count
  /// with a lower one — losing exactly the data this design protects.
  Future<int> deleteUploadedBefore(String day) {
    return (delete(productEventCounters)
          ..where(($ProductEventCountersTable t) =>
              t.syncStatus.equals(SyncStatus.synced) &
              t.day.isSmallerThanValue(day)))
        .go();
  }

  /// Drops every local counter.
  ///
  /// Called when the user opts out and at sign-out. Opting out has to remove
  /// what was already collected and not yet sent, otherwise "off" would still
  /// mean "the backlog goes out on the next flush". Sign-out matters for the
  /// same reason `clearUserData` wipes the conflict quarantine: these rows
  /// describe the previous account's behaviour and must not travel to the next
  /// account signed in on this device.
  Future<int> deleteAll() => delete(productEventCounters).go();
}
