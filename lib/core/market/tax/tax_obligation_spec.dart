/// One catalog entry: everything the generator needs to decide whether an
/// obligation applies to a taxpayer, how often it recurs, and when it is due.
///
/// The catalog is pure data. It has no I/O, no Flutter and no clock, so the
/// whole of it can be unit-tested, and so a market other than TR can be added
/// as one more list rather than as a branch in the generator.
library;

import 'package:smartspend/core/market/tax/due_rule.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

/// Whether an obligation applies to a given taxpayer.
enum TaxObligationApplicability {
  /// Every condition is met.
  applies,

  /// At least one condition is answered and not met. Decisive: the item is
  /// left out of the calendar.
  doesNotApply,

  /// No condition is violated but at least one is unanswered.
  ///
  /// Not the same as [doesNotApply], and the difference is the whole reason
  /// the wizard may be skipped: the calendar shows these as "might apply to
  /// you — finish your profile" rather than dropping them.
  unknown,
}

/// The conditions under which an obligation exists for a taxpayer.
///
/// Declarative rather than a predicate function, so the wizard can explain
/// *which* answer brought an item into the calendar, and so the conditions
/// themselves can be listed in the verification worksheet.
final class TaxObligationEligibility {
  const TaxObligationEligibility({
    this.legalForms,
    this.requiresVatLiability = false,
    this.requiresWithholdingLiability = false,
    this.requiresEmployer = false,
    this.requiresBagkur = false,
    this.requiresELedger = false,
    this.requiresVehicle = false,
    this.requiresRealEstate = false,
  });

  /// Applies to every taxpayer in the market.
  static const TaxObligationEligibility everyone = TaxObligationEligibility();

  /// Legal forms this obligation exists for; `null` means any form.
  ///
  /// ⚠️ The sets in the TR catalog are `[DOĞRULANACAK]` along with the dates —
  /// "which taxpayers file this" is as much a legal question as "by when".
  final Set<TaxpayerLegalForm>? legalForms;

  /// Requires a VAT liability (monthly or quarterly).
  final bool requiresVatLiability;

  /// Requires a withholding liability (monthly or quarterly).
  final bool requiresWithholdingLiability;

  /// Requires employing staff (SGK 4/a employer).
  final bool requiresEmployer;

  /// Requires personal Bağ-Kur (4/b) coverage.
  final bool requiresBagkur;

  /// Requires keeping books as e-Defter.
  final bool requiresELedger;

  /// Requires owning a vehicle.
  final bool requiresVehicle;

  /// Requires owning real estate.
  final bool requiresRealEstate;

  /// Evaluates the conditions against [profile].
  ///
  /// A single answered-and-failed condition wins over any number of unanswered
  /// ones: if the user says they have no staff, the employer filings are gone
  /// regardless of what else is blank.
  TaxObligationApplicability evaluate(TaxpayerProfile profile) {
    bool sawUnknown = false;

    final Set<TaxpayerLegalForm>? forms = legalForms;
    if (forms != null) {
      if (profile.legalForm == TaxpayerLegalForm.unspecified) {
        sawUnknown = true;
      } else if (!forms.contains(profile.legalForm)) {
        return TaxObligationApplicability.doesNotApply;
      }
    }

    if (requiresVatLiability) {
      switch (profile.vatLiability) {
        case VatLiability.none:
          return TaxObligationApplicability.doesNotApply;
        case VatLiability.unknown:
          sawUnknown = true;
        case VatLiability.monthly:
        case VatLiability.quarterly:
          break;
      }
    }

    if (requiresWithholdingLiability) {
      switch (profile.withholdingLiability) {
        case WithholdingLiability.none:
          return TaxObligationApplicability.doesNotApply;
        case WithholdingLiability.unknown:
          sawUnknown = true;
        case WithholdingLiability.monthly:
        case WithholdingLiability.quarterly:
          break;
      }
    }

    final List<bool> gates = <bool>[
      requiresEmployer,
      requiresBagkur,
      requiresELedger,
      requiresVehicle,
      requiresRealEstate,
    ];
    final List<TaxpayerAnswer> answers = <TaxpayerAnswer>[
      profile.employsStaff,
      profile.bagkurInsured,
      profile.usesELedger,
      profile.ownsVehicle,
      profile.ownsRealEstate,
    ];
    for (int i = 0; i < gates.length; i++) {
      if (!gates[i]) {
        continue;
      }
      switch (answers[i]) {
        case TaxpayerAnswer.no:
          return TaxObligationApplicability.doesNotApply;
        case TaxpayerAnswer.unknown:
          sawUnknown = true;
        case TaxpayerAnswer.yes:
          break;
      }
    }

    return sawUnknown
        ? TaxObligationApplicability.unknown
        : TaxObligationApplicability.applies;
  }
}

/// A catalog entry.
final class TaxObligationSpec {
  const TaxObligationSpec({
    required this.kind,
    required this.periodKind,
    required this.periodSource,
    required this.eligibility,
    required this.declaration,
    required this.payment,
    required this.sourceNote,
    this.occursOnlyWhenTransactionsExist = false,
    this.isUserDefined = false,
  });

  /// Which obligation this is.
  final TaxObligationKind kind;

  /// The recurrence used when [periodSource] is [TaxPeriodSource.fixed], and
  /// the fallback shown in documentation otherwise.
  final TaxPeriodKind periodKind;

  /// Where the recurrence comes from.
  final TaxPeriodSource periodSource;

  /// Who this obligation exists for.
  final TaxObligationEligibility eligibility;

  /// The filing deadline — or [NoDueDate] where there is no filing step.
  ///
  /// Separate from [payment] on purpose. They differ for most of this catalog,
  /// and about a third of the entries have one side and not the other;
  /// collapsing them into one field would make those entries lie.
  final DueSchedule declaration;

  /// The payment deadline — or [NoDueDate] where nothing is paid.
  final DueSchedule payment;

  /// What has to be confirmed, and against which source, before this entry's
  /// deadlines may become [ConfirmedDueDates]. Developer-facing.
  final String sourceNote;

  /// True where the obligation exists only in periods that actually had a
  /// qualifying transaction (KDV-2).
  ///
  /// The generator marks such items as conditional instead of asserting one
  /// every period, because "you owe a KDV-2 return this month" is false for
  /// most months of most taxpayers.
  final bool occursOnlyWhenTransactionsExist;

  /// True for the template of user-created items, which the generator skips.
  final bool isUserDefined;

  /// The recurrence for [profile], or `null` when the profile cannot say.
  TaxPeriodKind? resolvePeriodKind(TaxpayerProfile profile) =>
      resolveTaxPeriodKind(
        source: periodSource,
        fallback: periodKind,
        profile: profile,
      );

  /// Whether both deadlines of this entry have been confirmed against a
  /// primary source. Entries where a side is [NoDueDate] count as confirmed
  /// for that side — there is nothing to look up.
  bool get isVerified =>
      declaration is! UnverifiedDueDate && payment is! UnverifiedDueDate;
}
