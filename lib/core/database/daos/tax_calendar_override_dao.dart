import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/tables.dart';

part 'tax_calendar_override_dao.g.dart';

/// Accessor for [TaxCalendarOverrides] — the local copy of the server's
/// corrections to the deadline catalog (1.3.0, Block 4, T10).
///
/// 🚨 THE WHOLE TABLE IS REPLACED ON EVERY PULL, not merged. That is the only
/// mechanism by which a withdrawn override is withdrawn: the server retracts
/// an extension by deleting its row, and a merge would leave the client
/// applying a correction the authority has taken back. The replacement runs in
/// a transaction so a crash mid-write cannot leave the calendar half-corrected.
///
/// An empty table is the normal state and not an error — it means the catalog
/// stands as shipped.
@DriftAccessor(tables: <Type>[TaxCalendarOverrides])
class TaxCalendarOverrideDao extends DatabaseAccessor<AppDatabase>
    with _$TaxCalendarOverrideDaoMixin {
  TaxCalendarOverrideDao(super.db);

  /// Every override this device holds for [market].
  Future<List<TaxCalendarOverride>> getForMarket(String market) =>
      (select(taxCalendarOverrides)
            ..where(
              ($TaxCalendarOverridesTable t) => t.market.equals(market),
            ))
          .get();

  /// Every override, regardless of market. Used by tests and diagnostics.
  Future<List<TaxCalendarOverride>> getAll() =>
      select(taxCalendarOverrides).get();

  /// Re-emits on change, so a completed pull refreshes the calendar without
  /// the puller having to know who is watching.
  Stream<List<TaxCalendarOverride>> watchAll() =>
      select(taxCalendarOverrides).watch();

  /// Replaces this device's entire set of overrides for [market] with [rows].
  ///
  /// Scoped to one market rather than the whole table: a pull only ever asks
  /// about the active market, and a global wipe would delete another market's
  /// overrides on the strength of a response that said nothing about them.
  ///
  /// An empty [rows] is meaningful and is applied as written — it is how the
  /// server says "every correction has been withdrawn".
  Future<void> replaceMarket(
    String market,
    List<TaxCalendarOverridesCompanion> rows,
  ) {
    return transaction(() async {
      await (delete(taxCalendarOverrides)
            ..where(
              ($TaxCalendarOverridesTable t) => t.market.equals(market),
            ))
          .go();
      for (final TaxCalendarOverridesCompanion row in rows) {
        await into(taxCalendarOverrides).insert(row);
      }
    });
  }
}
