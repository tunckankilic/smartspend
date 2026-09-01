import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';

part 'tax_obligation_dao.g.dart';

/// Accessor for [TaxObligations] — the generated calendar and the user's marks
/// on it (1.3.0, Block 4).
///
/// One method carries the correctness of the feature: [upsertGenerated]. The
/// calendar is regenerated whenever the profile changes, a new period comes
/// into range, or an override arrives — and every regeneration passes over
/// items the user has already annotated. It therefore writes *only* the
/// generated fields and never touches [TaxObligations.declaredAt],
/// [TaxObligations.paidAt], [TaxObligations.dismissedAt],
/// [TaxObligations.note] or the amount. A regeneration that cleared a "paid"
/// mark would be indistinguishable, from the user's side, from the app losing
/// their data.
///
/// It also leaves a due date alone once the user has edited it: their
/// correction outranks the catalog, which is by construction the less
/// trustworthy of the two while the dates are unverified.
@DriftAccessor(tables: <Type>[TaxObligations])
class TaxObligationDao extends DatabaseAccessor<AppDatabase>
    with _$TaxObligationDaoMixin {
  TaxObligationDao(super.db);

  /// Every item, earliest period first.
  Future<List<TaxObligation>> getAll() => (select(taxObligations)
        ..orderBy(<OrderClauseGenerator<$TaxObligationsTable>>[
          ($TaxObligationsTable t) => OrderingTerm.asc(t.periodStart),
          ($TaxObligationsTable t) => OrderingTerm.asc(t.installmentIndex),
        ]))
      .get();

  /// Items whose filing or payment deadline falls within [from]..[to].
  ///
  /// An item with neither date — an obligation whose rule is not confirmed —
  /// is matched on its period instead, so it stays visible rather than
  /// disappearing from every range at once.
  Future<List<TaxObligation>> getDueBetween(DateTime from, DateTime to) {
    final DateTime start = from.toUtc();
    final DateTime end = to.toUtc();
    return (select(taxObligations)
          ..where(
            ($TaxObligationsTable t) =>
                t.declarationDueDate.isBetweenValues(start, end) |
                t.paymentDueDate.isBetweenValues(start, end) |
                (t.declarationDueDate.isNull() &
                    t.paymentDueDate.isNull() &
                    t.periodEnd.isBetweenValues(start, end)),
          )
          ..orderBy(<OrderClauseGenerator<$TaxObligationsTable>>[
            ($TaxObligationsTable t) => OrderingTerm.asc(t.periodStart),
            ($TaxObligationsTable t) => OrderingTerm.asc(t.installmentIndex),
          ]))
        .get();
  }

  /// Every item, re-emitted on change.
  Stream<List<TaxObligation>> watchAll() => (select(taxObligations)
        ..orderBy(<OrderClauseGenerator<$TaxObligationsTable>>[
          ($TaxObligationsTable t) => OrderingTerm.asc(t.periodStart),
          ($TaxObligationsTable t) => OrderingTerm.asc(t.installmentIndex),
        ]))
      .watch();

  /// The item with [generationKey], if this device has it.
  Future<TaxObligation?> findByGenerationKey(String generationKey) {
    return (select(taxObligations)
          ..where(
            ($TaxObligationsTable t) => t.generationKey.equals(generationKey),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Writes a generated item, preserving everything the user put on it.
  ///
  /// Returns the local row id. On an existing row this updates the period, the
  /// deadlines and the catalog metadata only; the user's marks, note and
  /// amount are not in the companion at all, so there is no path by which a
  /// regeneration can clear them.
  ///
  /// [declarationDueDate] and [paymentDueDate] may be null — that is the
  /// honest state of an obligation whose rule is not confirmed, and it must be
  /// storable. A user-edited date (`dueDateSource == 'user'`) survives
  /// regeneration untouched.
  Future<int> upsertGenerated({
    required String generationKey,
    required String kind,
    required String periodKind,
    required DateTime periodStart,
    required DateTime periodEnd,
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
    String dueDateSource = 'catalog',
    int installmentIndex = 0,
    String? userId,
    DateTime? now,
  }) async {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    final TaxObligation? existing = await findByGenerationKey(generationKey);

    if (existing == null) {
      return into(taxObligations).insert(
        TaxObligationsCompanion.insert(
          userId: Value<String?>(userId),
          generationKey: generationKey,
          kind: kind,
          periodKind: periodKind,
          periodStart: periodStart.toUtc(),
          periodEnd: periodEnd.toUtc(),
          installmentIndex: Value<int>(installmentIndex),
          declarationDueDate: Value<DateTime?>(declarationDueDate?.toUtc()),
          paymentDueDate: Value<DateTime?>(paymentDueDate?.toUtc()),
          dueDateSource: Value<String>(dueDateSource),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
    }

    // The user's own date wins over the catalog's. Theirs came from their
    // accountant; ours is a rule nobody has verified yet.
    final bool keepDates = existing.dueDateSource == 'user';

    await (update(taxObligations)
          ..where(($TaxObligationsTable t) => t.id.equals(existing.id)))
        .write(
      TaxObligationsCompanion(
        kind: Value<String>(kind),
        periodKind: Value<String>(periodKind),
        periodStart: Value<DateTime>(periodStart.toUtc()),
        periodEnd: Value<DateTime>(periodEnd.toUtc()),
        installmentIndex: Value<int>(installmentIndex),
        declarationDueDate: keepDates
            ? const Value<DateTime?>.absent()
            : Value<DateTime?>(declarationDueDate?.toUtc()),
        paymentDueDate: keepDates
            ? const Value<DateTime?>.absent()
            : Value<DateTime?>(paymentDueDate?.toUtc()),
        dueDateSource: keepDates
            ? const Value<String>.absent()
            : Value<String>(dueDateSource),
        updatedAt: Value<DateTime>(stamp),
        syncStatus: Value<String>(
          existing.remoteId == null
              ? SyncStatus.pendingCreate
              : SyncStatus.pendingUpdate,
        ),
      ),
    );
    return existing.id;
  }

  /// Adds an item the user created themselves.
  Future<int> insertUserDefined({
    required String generationKey,
    required String title,
    required DateTime periodStart,
    required DateTime periodEnd,
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
    String? note,
    String? userId,
    DateTime? now,
  }) {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    return into(taxObligations).insert(
      TaxObligationsCompanion.insert(
        userId: Value<String?>(userId),
        generationKey: generationKey,
        kind: 'custom',
        periodKind: 'one_off',
        periodStart: periodStart.toUtc(),
        periodEnd: periodEnd.toUtc(),
        declarationDueDate: Value<DateTime?>(declarationDueDate?.toUtc()),
        paymentDueDate: Value<DateTime?>(paymentDueDate?.toUtc()),
        dueDateSource: const Value<String>('user'),
        title: Value<String?>(title),
        note: Value<String?>(note),
        isUserDefined: const Value<bool>(true),
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
  }

  /// Marks the item filed, or clears the mark when [at] is null.
  ///
  /// Filing and paying are separate acts, days apart. Nothing here touches
  /// [TaxObligations.paidAt].
  Future<void> setDeclaredAt(int id, DateTime? at, {DateTime? now}) =>
      _annotate(id, TaxObligationsCompanion(
        declaredAt: Value<DateTime?>(at?.toUtc()),
      ), now);

  /// Marks the item paid, or clears the mark.
  Future<void> setPaidAt(int id, DateTime? at, {DateTime? now}) =>
      _annotate(id, TaxObligationsCompanion(
        paidAt: Value<DateTime?>(at?.toUtc()),
      ), now);

  /// Records that the user says this item does not apply to them.
  ///
  /// Kept rather than deleted: it is the clearest signal that the generated
  /// calendar is wrong for this taxpayer, and a deleted row would be
  /// regenerated on the next run anyway.
  Future<void> setDismissedAt(int id, DateTime? at, {DateTime? now}) =>
      _annotate(id, TaxObligationsCompanion(
        dismissedAt: Value<DateTime?>(at?.toUtc()),
      ), now);

  /// Sets the amount and who says so, or clears both.
  ///
  /// There is no source for "the app worked it out": see `TaxAmountSource`.
  Future<void> setAmount(
    int id, {
    required int? amountMinor,
    required String amountSource,
    DateTime? now,
  }) =>
      _annotate(id, TaxObligationsCompanion(
        amountMinor: Value<int?>(amountMinor),
        amountSource: Value<String>(amountSource),
      ), now);

  /// Sets the user's note.
  Future<void> setNote(int id, String? note, {DateTime? now}) =>
      _annotate(id, TaxObligationsCompanion(note: Value<String?>(note)), now);

  /// Replaces the deadlines with the user's own and stamps the source.
  Future<void> setUserDueDates(
    int id, {
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
    DateTime? now,
  }) =>
      _annotate(id, TaxObligationsCompanion(
        declarationDueDate: Value<DateTime?>(declarationDueDate?.toUtc()),
        paymentDueDate: Value<DateTime?>(paymentDueDate?.toUtc()),
        dueDateSource: const Value<String>('user'),
      ), now);

  /// Rows the sync engine still has to push.
  Future<List<TaxObligation>> getPendingSync() => (select(taxObligations)
        ..where(
          ($TaxObligationsTable t) =>
              t.syncStatus.isNotValue(SyncStatus.synced),
        ))
      .get();

  Future<void> _annotate(
    int id,
    TaxObligationsCompanion values,
    DateTime? now,
  ) async {
    final TaxObligation? existing = await (select(taxObligations)
          ..where(($TaxObligationsTable t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      return;
    }
    await (update(taxObligations)
          ..where(($TaxObligationsTable t) => t.id.equals(id)))
        .write(
      values.copyWith(
        updatedAt: Value<DateTime>((now ?? DateTime.now()).toUtc()),
        syncStatus: Value<String>(
          existing.remoteId == null
              ? SyncStatus.pendingCreate
              : SyncStatus.pendingUpdate,
        ),
      ),
    );
  }
}
