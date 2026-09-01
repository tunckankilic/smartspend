import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/database/tables.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

part 'tax_profile_dao.g.dart';

/// Accessor for [TaxProfiles] — the taxpayer's eight answers (1.3.0, Block 4).
///
/// The table holds one row: this device's user has one taxpayer profile, and
/// from 1.4.0 one per company. [save] is therefore an update-or-insert against
/// that single row rather than an append, and [watch] hands the calendar a
/// stream so a wizard answer redraws it without a manual refresh.
///
/// Answers cross this boundary as enums, never as strings. Text is what the
/// column stores; a caller cannot hand in `'evet'` and have it silently become
/// a value no reader understands.
@DriftAccessor(tables: <Type>[TaxProfiles])
class TaxProfileDao extends DatabaseAccessor<AppDatabase>
    with _$TaxProfileDaoMixin {
  TaxProfileDao(super.db);

  /// The stored profile, or `null` when the wizard has never been opened.
  Future<TaxProfile?> getRow() =>
      (select(taxProfiles)..limit(1)).getSingleOrNull();

  /// The stored answers, or [TaxpayerProfile.empty] when there is no row.
  ///
  /// Never null: "no profile yet" and "a profile with nothing answered"
  /// generate the same calendar, and callers that had to tell them apart
  /// would all write the same fallback.
  Future<TaxpayerProfile> getProfile() async =>
      _toProfile(await getRow());

  /// The answers, re-emitted whenever they change.
  Stream<TaxpayerProfile> watchProfile() => (select(taxProfiles)..limit(1))
      .watchSingleOrNull()
      .map(_toProfile);

  /// Writes [profile], creating the row on first save.
  ///
  /// Stamps the row pending so the sync engine picks it up. [userId] is left
  /// alone when null so a save made before sign-in does not erase an owner the
  /// pull already wrote.
  Future<void> save(
    TaxpayerProfile profile, {
    String? userId,
    DateTime? now,
  }) async {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    final TaxProfile? existing = await getRow();
    if (existing == null) {
      await into(taxProfiles).insert(
        TaxProfilesCompanion.insert(
          userId: Value<String?>(userId),
          legalForm: Value<String>(profile.legalForm.wireValue),
          vatLiability: Value<String>(profile.vatLiability.wireValue),
          withholdingLiability:
              Value<String>(profile.withholdingLiability.wireValue),
          employsStaff: Value<String>(profile.employsStaff.wireValue),
          bagkurInsured: Value<String>(profile.bagkurInsured.wireValue),
          usesELedger: Value<String>(profile.usesELedger.wireValue),
          ownsVehicle: Value<String>(profile.ownsVehicle.wireValue),
          ownsRealEstate: Value<String>(profile.ownsRealEstate.wireValue),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      return;
    }
    await (update(taxProfiles)
          ..where(($TaxProfilesTable t) => t.id.equals(existing.id)))
        .write(
      TaxProfilesCompanion(
        userId: userId == null
            ? const Value<String?>.absent()
            : Value<String?>(userId),
        legalForm: Value<String>(profile.legalForm.wireValue),
        vatLiability: Value<String>(profile.vatLiability.wireValue),
        withholdingLiability:
            Value<String>(profile.withholdingLiability.wireValue),
        employsStaff: Value<String>(profile.employsStaff.wireValue),
        bagkurInsured: Value<String>(profile.bagkurInsured.wireValue),
        usesELedger: Value<String>(profile.usesELedger.wireValue),
        ownsVehicle: Value<String>(profile.ownsVehicle.wireValue),
        ownsRealEstate: Value<String>(profile.ownsRealEstate.wireValue),
        updatedAt: Value<DateTime>(stamp),
        syncStatus: Value<String>(
          existing.remoteId == null
              ? SyncStatus.pendingCreate
              : SyncStatus.pendingUpdate,
        ),
      ),
    );
  }

  /// Rows the sync engine still has to push.
  Future<List<TaxProfile>> getPendingSync() => (select(taxProfiles)
        ..where(
          ($TaxProfilesTable t) => t.syncStatus.isNotValue(SyncStatus.synced),
        ))
      .get();

  /// Reads a stored row back into the domain value.
  ///
  /// Unrecognised text degrades to "unknown" rather than throwing: a row
  /// written by a newer client — or, later, by a device that knows a legal
  /// form this build does not — must leave the app usable instead of taking
  /// the calendar down with it.
  static TaxpayerProfile _toProfile(TaxProfile? row) {
    if (row == null) {
      return TaxpayerProfile.empty;
    }
    return TaxpayerProfile(
      legalForm: TaxpayerLegalForm.fromWireValue(row.legalForm),
      vatLiability: VatLiability.fromWireValue(row.vatLiability),
      withholdingLiability:
          WithholdingLiability.fromWireValue(row.withholdingLiability),
      employsStaff: TaxpayerAnswer.fromWireValue(row.employsStaff),
      bagkurInsured: TaxpayerAnswer.fromWireValue(row.bagkurInsured),
      usesELedger: TaxpayerAnswer.fromWireValue(row.usesELedger),
      ownsVehicle: TaxpayerAnswer.fromWireValue(row.ownsVehicle),
      ownsRealEstate: TaxpayerAnswer.fromWireValue(row.ownsRealEstate),
    );
  }
}
