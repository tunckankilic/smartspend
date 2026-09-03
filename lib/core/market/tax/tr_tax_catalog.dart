/// The Turkish obligation catalog.
///
/// # 🚨 No date in this file is confirmed
///
/// Every deadline below is an [UnverifiedDueDate]: the *shape* of the calendar
/// is settled, the numbers are not. That is deliberate and it is enforced by
/// the type — [UnverifiedDueDate] has nowhere to put a day of the month, so a
/// plausible-looking guess cannot be parked here "temporarily" and then ship.
///
/// Confirming an entry means three things, in order:
///
/// 1. Fill that entry's row in `docs/internal/pivot/KATALOG_TEYIT.md` from a
///    primary source (GİB's own calendar and the relevant circular, or a
///    licensed SMMM's written answer). The worksheet asks for the filing day,
///    the payment day, the period, who it applies to, and the source.
/// 2. Replace the entry's [UnverifiedDueDate] with [ConfirmedDueDates],
///    quoting that source in `source`.
/// 3. Leave the entries you did not confirm alone. A half-confirmed catalog is
///    fine — items with an unconfirmed deadline appear without a date and say
///    so, which is the intended degraded state, not a bug.
///
/// The eligibility conditions carry the same caveat: "which taxpayers file
/// this" is a legal question, not a modelling one, and the sets below are the
/// working assumption the worksheet asks to check.
///
/// Deadlines here are also *undeferred*: none of them account for weekends,
/// public holidays or the mali tatil. That shift is the deferral engine's job
/// (T5) and happens after a rule resolves to a date.
library;

import 'package:smartspend/core/market/tax/due_rule.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_spec.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

/// Marker used in every unconfirmed note so the remaining work is one grep.
const String kUnverifiedMarker = '[DOĞRULANACAK]';

/// Every obligation SmartSpend knows about in Türkiye.
///
/// One entry per [TaxObligationKind]; a test pins that correspondence so a new
/// kind cannot be added without deciding when it is due.
const List<TaxObligationSpec> trTaxObligations = <TaxObligationSpec>[
  TaxObligationSpec(
    kind: TaxObligationKind.kdv1,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.vatLiability,
    eligibility: TaxObligationEligibility(requiresVatLiability: true),
    declaration: UnverifiedDueDate('$kUnverifiedMarker KDV-1 filing day'),
    payment: UnverifiedDueDate('$kUnverifiedMarker KDV-1 payment day'),
    sourceNote: '$kUnverifiedMarker GİB filing calendar: KDV-1 filing and '
        'payment days, and whether the quarterly regime shares them.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.kdv2,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(requiresVatLiability: true),
    declaration: UnverifiedDueDate('$kUnverifiedMarker KDV-2 filing day'),
    payment: UnverifiedDueDate('$kUnverifiedMarker KDV-2 payment day'),
    occursOnlyWhenTransactionsExist: true,
    sourceNote: '$kUnverifiedMarker KDV-2 filing and payment days; also '
        'confirm it is monthly for every taxpayer who has one, and who is '
        'required to file it at all (withholding buyers).',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.mphb,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.withholdingLiability,
    eligibility:
        TaxObligationEligibility(requiresWithholdingLiability: true),
    declaration: UnverifiedDueDate('$kUnverifiedMarker MPHB filing day'),
    payment: UnverifiedDueDate('$kUnverifiedMarker MPHB payment day'),
    sourceNote: '$kUnverifiedMarker MPHB filing and payment days, and the '
        'conditions under which the quarterly regime is available.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.sgk4a,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(requiresEmployer: true),
    declaration: UnverifiedDueDate('$kUnverifiedMarker does the 4/a premium '
        'have a filing step of its own, or is it entirely inside MPHB? If the '
        'latter, this becomes NoDueDate.'),
    payment: UnverifiedDueDate('$kUnverifiedMarker SGK 4/a premium payment '
        'day'),
    sourceNote: '$kUnverifiedMarker SGK employer premium payment day.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.bagkur,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(requiresBagkur: true),
    declaration: NoDueDate('Bağ-Kur (4/b) premiums are assessed, not '
        'declared: the insured person files nothing.'),
    payment: UnverifiedDueDate('$kUnverifiedMarker Bağ-Kur premium payment '
        'day'),
    sourceNote: '$kUnverifiedMarker Bağ-Kur premium payment day.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.gecici,
    periodKind: TaxPeriodKind.quarterly,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(
      legalForms: <TaxpayerLegalForm>{
        TaxpayerLegalForm.sahisSirketi,
        TaxpayerLegalForm.serbestMeslek,
        TaxpayerLegalForm.limited,
        TaxpayerLegalForm.anonim,
        TaxpayerLegalForm.diger,
      },
    ),
    declaration: UnverifiedDueDate('$kUnverifiedMarker geçici vergi filing '
        'day, and how many quarters the year has for this purpose'),
    payment: UnverifiedDueDate('$kUnverifiedMarker geçici vergi payment day'),
    sourceNote: '$kUnverifiedMarker geçici vergi: number of periods per year, '
        'filing and payment days, and whether basit usul is excluded as '
        'assumed here.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.yillikGv,
    periodKind: TaxPeriodKind.annual,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(
      legalForms: <TaxpayerLegalForm>{
        TaxpayerLegalForm.sahisSirketi,
        TaxpayerLegalForm.serbestMeslek,
        TaxpayerLegalForm.diger,
      },
    ),
    declaration: UnverifiedDueDate('$kUnverifiedMarker annual income tax '
        'filing deadline'),
    payment: UnverifiedDueDate('$kUnverifiedMarker annual income tax payment '
        'deadlines — how many installments, and in which months'),
    sourceNote: '$kUnverifiedMarker annual income tax: filing window, '
        'installment count and payment months.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.kurumlar,
    periodKind: TaxPeriodKind.annual,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(
      legalForms: <TaxpayerLegalForm>{
        TaxpayerLegalForm.limited,
        TaxpayerLegalForm.anonim,
      },
    ),
    declaration: UnverifiedDueDate('$kUnverifiedMarker corporate tax filing '
        'deadline'),
    payment: UnverifiedDueDate('$kUnverifiedMarker corporate tax payment '
        'deadline(s)'),
    sourceNote: '$kUnverifiedMarker corporate tax filing window and payment '
        'deadline; also whether a non-calendar fiscal year shifts them.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.damga,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(
      legalForms: <TaxpayerLegalForm>{
        TaxpayerLegalForm.limited,
        TaxpayerLegalForm.anonim,
        TaxpayerLegalForm.diger,
      },
    ),
    declaration: UnverifiedDueDate('$kUnverifiedMarker stamp duty filing day'),
    payment: UnverifiedDueDate('$kUnverifiedMarker stamp duty payment day'),
    sourceNote: '$kUnverifiedMarker stamp duty: who has a continuous '
        'liability (the legal forms above are an assumption), period, filing '
        'and payment days.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.basitUsul,
    periodKind: TaxPeriodKind.annual,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(
      legalForms: <TaxpayerLegalForm>{TaxpayerLegalForm.basitUsul},
    ),
    declaration: UnverifiedDueDate('$kUnverifiedMarker basit usul annual '
        'filing deadline'),
    payment: UnverifiedDueDate('$kUnverifiedMarker basit usul payment '
        'deadlines — how many installments, and in which months'),
    sourceNote: '$kUnverifiedMarker basit usul: filing window, installment '
        'count and payment months.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.edefterBerat,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(requiresELedger: true),
    declaration: UnverifiedDueDate('$kUnverifiedMarker e-ledger berat upload '
        'deadline, and whether the three-month batching option changes the '
        'period for taxpayers who take it'),
    payment: NoDueDate('The berat is a seal uploaded to GİB. Nothing is '
        'paid.'),
    sourceNote: '$kUnverifiedMarker e-Defter berat upload deadline and the '
        'batching option.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.babs,
    periodKind: TaxPeriodKind.monthly,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(
      legalForms: <TaxpayerLegalForm>{
        TaxpayerLegalForm.limited,
        TaxpayerLegalForm.anonim,
        TaxpayerLegalForm.diger,
      },
    ),
    declaration: UnverifiedDueDate('$kUnverifiedMarker Form Ba/Bs filing day'),
    payment: NoDueDate('Ba/Bs are informational listings. Nothing is paid.'),
    sourceNote: '$kUnverifiedMarker Form Ba/Bs: who must file (the legal '
        'forms above are an assumption — the real test is the bookkeeping '
        'regime), filing day, and the reporting threshold.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.mtv,
    periodKind: TaxPeriodKind.annual,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(requiresVehicle: true),
    declaration: UnverifiedDueDate('$kUnverifiedMarker does MTV have a '
        'recurring filing step at all? If it is assessed automatically, this '
        'becomes NoDueDate.'),
    payment: UnverifiedDueDate('$kUnverifiedMarker MTV payment deadlines — '
        'how many installments, and in which months'),
    sourceNote: '$kUnverifiedMarker MTV installment count and payment months.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.emlak,
    periodKind: TaxPeriodKind.annual,
    periodSource: TaxPeriodSource.fixed,
    eligibility: TaxObligationEligibility(requiresRealEstate: true),
    declaration: UnverifiedDueDate('$kUnverifiedMarker property tax is '
        'declared on acquisition rather than annually — confirm whether a '
        'recurring filing step exists. If not, this becomes NoDueDate.'),
    payment: UnverifiedDueDate('$kUnverifiedMarker property tax payment '
        'deadlines — how many installments, and in which months'),
    sourceNote: '$kUnverifiedMarker property tax installment count and '
        'payment months. Note the municipality, not GİB, collects it.',
  ),
  TaxObligationSpec(
    kind: TaxObligationKind.custom,
    periodKind: TaxPeriodKind.oneOff,
    periodSource: TaxPeriodSource.userDefined,
    eligibility: TaxObligationEligibility.everyone,
    declaration: NoDueDate('A user-defined item carries the dates the user '
        'entered; the catalog has no rule for it.'),
    payment: NoDueDate('A user-defined item carries the dates the user '
        'entered; the catalog has no rule for it.'),
    isUserDefined: true,
    sourceNote: 'Template for user-created items (4b/T9). Never generated '
        'from a profile.',
  ),
];
