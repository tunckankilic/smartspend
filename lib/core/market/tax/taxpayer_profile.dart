/// What the app needs to know about a taxpayer to generate their calendar.
///
/// Eight dimensions, one per question in the profile wizard (4b/T6). Every one
/// of them has an "unknown" value and every question is skippable, because a
/// half-filled profile has to produce a partial calendar rather than an error
/// — the wizard is also the D-2 measurement instrument, and a wizard that
/// punishes skipping measures nothing.
///
/// Pure data: no Drift, no Flutter. The `tax_profiles` table (T2) maps onto
/// this; the generator (T4) only ever sees this.
library;

import 'package:smartspend/core/services/telemetry_service.dart';

/// A yes/no question the user is allowed not to answer.
enum TaxpayerAnswer {
  /// Answered yes.
  yes('yes'),

  /// Answered no.
  no('no'),

  /// Not answered, or answered "I don't know".
  unknown('unknown');

  const TaxpayerAnswer(this.wireValue);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// Parses a persisted value; anything unrecognised reads as [unknown], so a
  /// row written by a newer client stays readable.
  static TaxpayerAnswer fromWireValue(String? value) {
    for (final TaxpayerAnswer answer in TaxpayerAnswer.values) {
      if (answer.wireValue == value) {
        return answer;
      }
    }
    return TaxpayerAnswer.unknown;
  }
}

/// Legal form of the business.
///
/// The values mirror [TelemetryDimension] one for one — see
/// [TaxpayerLegalForm.telemetryDimension]. They are the buckets D-2 is
/// answered in, so the two lists drifting apart would quietly corrupt the
/// measurement; a test pins the correspondence.
enum TaxpayerLegalForm {
  /// Sole proprietorship (şahıs şirketi).
  sahisSirketi('sahis_sirketi', TelemetryDimension.sahisSirketi),

  /// Limited company (Ltd. Şti.).
  limited('limited', TelemetryDimension.limited),

  /// Joint-stock company (A.Ş.).
  anonim('anonim', TelemetryDimension.anonim),

  /// Self-employed professional (serbest meslek erbabı).
  serbestMeslek('serbest_meslek', TelemetryDimension.serbestMeslek),

  /// Simplified regime (basit usul).
  basitUsul('basit_usul', TelemetryDimension.basitUsul),

  /// A form outside the list above.
  diger('diger', TelemetryDimension.diger),

  /// Question skipped.
  unspecified('belirtilmedi', TelemetryDimension.belirtilmedi);

  const TaxpayerLegalForm(this.wireValue, this.telemetryDimension);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// The bucket this form is counted in when `tax_profile_completed` fires.
  final TelemetryDimension telemetryDimension;

  /// Parses a persisted value; unrecognised reads as [unspecified].
  static TaxpayerLegalForm fromWireValue(String? value) {
    for (final TaxpayerLegalForm form in TaxpayerLegalForm.values) {
      if (form.wireValue == value) {
        return form;
      }
    }
    return TaxpayerLegalForm.unspecified;
  }
}

/// How often the taxpayer files VAT, which is also whether they file it.
enum VatLiability {
  /// Monthly VAT return.
  monthly('monthly'),

  /// Quarterly VAT return.
  quarterly('quarterly'),

  /// Not a VAT taxpayer.
  none('none'),

  /// Question skipped.
  unknown('unknown');

  const VatLiability(this.wireValue);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// Parses a persisted value; unrecognised reads as [unknown].
  static VatLiability fromWireValue(String? value) {
    for (final VatLiability liability in VatLiability.values) {
      if (liability.wireValue == value) {
        return liability;
      }
    }
    return VatLiability.unknown;
  }
}

/// How often the taxpayer files withholding (muhtasar ve prim hizmet
/// beyannamesi), which is also whether they file it.
enum WithholdingLiability {
  /// Monthly filing.
  monthly('monthly'),

  /// Quarterly filing.
  quarterly('quarterly'),

  /// No withholding liability.
  none('none'),

  /// Question skipped.
  unknown('unknown');

  const WithholdingLiability(this.wireValue);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// Parses a persisted value; unrecognised reads as [unknown].
  static WithholdingLiability fromWireValue(String? value) {
    for (final WithholdingLiability liability in WithholdingLiability.values) {
      if (liability.wireValue == value) {
        return liability;
      }
    }
    return WithholdingLiability.unknown;
  }
}

/// The eight answers, as one immutable value.
///
/// Defaults are all "unknown": [TaxpayerProfile.empty] is what a user who has
/// never opened the wizard has, and it must be a legal input to the generator.
final class TaxpayerProfile {
  const TaxpayerProfile({
    this.legalForm = TaxpayerLegalForm.unspecified,
    this.vatLiability = VatLiability.unknown,
    this.withholdingLiability = WithholdingLiability.unknown,
    this.employsStaff = TaxpayerAnswer.unknown,
    this.bagkurInsured = TaxpayerAnswer.unknown,
    this.usesELedger = TaxpayerAnswer.unknown,
    this.ownsVehicle = TaxpayerAnswer.unknown,
    this.ownsRealEstate = TaxpayerAnswer.unknown,
  });

  /// Nothing answered — the state of every user before the wizard.
  static const TaxpayerProfile empty = TaxpayerProfile();

  /// Q1 — legal form.
  final TaxpayerLegalForm legalForm;

  /// Q2 — VAT liability and its frequency.
  final VatLiability vatLiability;

  /// Q3 — withholding liability and its frequency.
  final WithholdingLiability withholdingLiability;

  /// Q4 — employs staff, i.e. is an SGK 4/a employer.
  final TaxpayerAnswer employsStaff;

  /// Q5 — pays Bağ-Kur (4/b) premiums personally.
  final TaxpayerAnswer bagkurInsured;

  /// Q6 — keeps books as e-Defter, which is what creates the berat deadline.
  final TaxpayerAnswer usesELedger;

  /// Q7 — owns a vehicle registered to the business or the person (MTV).
  final TaxpayerAnswer ownsVehicle;

  /// Q8 — owns real estate (emlak vergisi).
  final TaxpayerAnswer ownsRealEstate;

  /// Whether every question has an answer.
  ///
  /// Not a gate on anything: an incomplete profile still generates the items
  /// it can. It exists so the UI can offer to finish the wizard, and so the
  /// generator can label a calendar as partial.
  bool get isComplete =>
      legalForm != TaxpayerLegalForm.unspecified &&
      vatLiability != VatLiability.unknown &&
      withholdingLiability != WithholdingLiability.unknown &&
      employsStaff != TaxpayerAnswer.unknown &&
      bagkurInsured != TaxpayerAnswer.unknown &&
      usesELedger != TaxpayerAnswer.unknown &&
      ownsVehicle != TaxpayerAnswer.unknown &&
      ownsRealEstate != TaxpayerAnswer.unknown;

  /// How many of the eight questions are answered.
  int get answeredCount => <bool>[
        legalForm != TaxpayerLegalForm.unspecified,
        vatLiability != VatLiability.unknown,
        withholdingLiability != WithholdingLiability.unknown,
        employsStaff != TaxpayerAnswer.unknown,
        bagkurInsured != TaxpayerAnswer.unknown,
        usesELedger != TaxpayerAnswer.unknown,
        ownsVehicle != TaxpayerAnswer.unknown,
        ownsRealEstate != TaxpayerAnswer.unknown,
      ].where((bool answered) => answered).length;

  /// The number of questions the wizard asks. Pinned by a test against the
  /// field count so adding a ninth dimension cannot silently skip the wizard.
  static const int questionCount = 8;

  /// Copy with individual answers replaced.
  TaxpayerProfile copyWith({
    TaxpayerLegalForm? legalForm,
    VatLiability? vatLiability,
    WithholdingLiability? withholdingLiability,
    TaxpayerAnswer? employsStaff,
    TaxpayerAnswer? bagkurInsured,
    TaxpayerAnswer? usesELedger,
    TaxpayerAnswer? ownsVehicle,
    TaxpayerAnswer? ownsRealEstate,
  }) =>
      TaxpayerProfile(
        legalForm: legalForm ?? this.legalForm,
        vatLiability: vatLiability ?? this.vatLiability,
        withholdingLiability: withholdingLiability ?? this.withholdingLiability,
        employsStaff: employsStaff ?? this.employsStaff,
        bagkurInsured: bagkurInsured ?? this.bagkurInsured,
        usesELedger: usesELedger ?? this.usesELedger,
        ownsVehicle: ownsVehicle ?? this.ownsVehicle,
        ownsRealEstate: ownsRealEstate ?? this.ownsRealEstate,
      );
}
