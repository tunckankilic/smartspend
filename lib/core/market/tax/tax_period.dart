/// How often an obligation recurs, and where that frequency comes from.
library;

import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

/// The recurrence of an obligation.
enum TaxPeriodKind {
  /// One period per calendar month.
  monthly('monthly', 1),

  /// Three-month periods aligned to the calendar year (Jan–Mar, Apr–Jun, …).
  quarterly('quarterly', 3),

  /// One period per calendar year.
  annual('annual', 12),

  /// No recurrence — a single dated item the user entered themselves.
  oneOff('one_off', 0);

  const TaxPeriodKind(this.wireValue, this.monthsPerPeriod);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// Length of one period in months; 0 for [oneOff].
  final int monthsPerPeriod;

  /// Parses a persisted value; unrecognised reads as [oneOff], which generates
  /// nothing rather than inventing a recurrence.
  static TaxPeriodKind fromWireValue(String? value) {
    for (final TaxPeriodKind kind in TaxPeriodKind.values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    return TaxPeriodKind.oneOff;
  }
}

/// Where an obligation's recurrence is decided.
///
/// Most obligations recur the same way for everyone. Two do not: VAT and
/// withholding are monthly or quarterly depending on the taxpayer, which is
/// exactly why those two are dimensions of [TaxpayerProfile] rather than
/// yes/no questions.
enum TaxPeriodSource {
  /// Same for every taxpayer.
  fixed,

  /// Follows [TaxpayerProfile.vatLiability].
  vatLiability,

  /// Follows [TaxpayerProfile.withholdingLiability].
  withholdingLiability,

  /// The user picks it (custom items).
  userDefined,
}

/// Resolves the recurrence of an obligation for one taxpayer.
///
/// Returns `null` when the profile does not answer the question the source
/// depends on. A null recurrence means "we cannot say how often this happens
/// for you", which the generator surfaces as a gap in the calendar instead of
/// filling in with the more common of the two options.
TaxPeriodKind? resolveTaxPeriodKind({
  required TaxPeriodSource source,
  required TaxPeriodKind fallback,
  required TaxpayerProfile profile,
}) {
  switch (source) {
    case TaxPeriodSource.fixed:
      return fallback;
    case TaxPeriodSource.vatLiability:
      switch (profile.vatLiability) {
        case VatLiability.monthly:
          return TaxPeriodKind.monthly;
        case VatLiability.quarterly:
          return TaxPeriodKind.quarterly;
        case VatLiability.none:
        case VatLiability.unknown:
          return null;
      }
    case TaxPeriodSource.withholdingLiability:
      switch (profile.withholdingLiability) {
        case WithholdingLiability.monthly:
          return TaxPeriodKind.monthly;
        case WithholdingLiability.quarterly:
          return TaxPeriodKind.quarterly;
        case WithholdingLiability.none:
        case WithholdingLiability.unknown:
          return null;
      }
    case TaxPeriodSource.userDefined:
      return null;
  }
}
