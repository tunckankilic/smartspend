import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_profile_wizard_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Enum → localized string, in one place.
///
/// The generated `AppLocalizations` has no dynamic key lookup, so every enum
/// that reaches the screen needs an explicit switch. Keeping them together
/// means adding an obligation is one compile error in one file rather than a
/// silently untranslated label somewhere in the tree — the switches are
/// exhaustive, so the compiler finds them.

/// Display name for an obligation.
///
/// User-created items carry the name the user typed; generated ones follow
/// the app language, because the obligation is the same thing in every
/// language and the user may have switched since it was generated.
String taxItemName(AppLocalizations l, TaxCalendarItem item) {
  final String? title = item.title;
  if (item.isUserDefined && title != null && title.isNotEmpty) {
    return title;
  }
  return taxObligationName(l, item.kind);
}

/// Display name for an obligation kind.
String taxObligationName(AppLocalizations l, TaxObligationKind kind) {
  switch (kind) {
    case TaxObligationKind.kdv1:
      return l.taxObligationKdv1;
    case TaxObligationKind.kdv2:
      return l.taxObligationKdv2;
    case TaxObligationKind.mphb:
      return l.taxObligationMphb;
    case TaxObligationKind.sgk4a:
      return l.taxObligationSgk4a;
    case TaxObligationKind.bagkur:
      return l.taxObligationBagkur;
    case TaxObligationKind.gecici:
      return l.taxObligationGecici;
    case TaxObligationKind.yillikGv:
      return l.taxObligationYillikGv;
    case TaxObligationKind.kurumlar:
      return l.taxObligationKurumlar;
    case TaxObligationKind.damga:
      return l.taxObligationDamga;
    case TaxObligationKind.basitUsul:
      return l.taxObligationBasitUsul;
    case TaxObligationKind.edefterBerat:
      return l.taxObligationEdefterBerat;
    case TaxObligationKind.babs:
      return l.taxObligationBabs;
    case TaxObligationKind.mtv:
      return l.taxObligationMtv;
    case TaxObligationKind.emlak:
      return l.taxObligationEmlak;
    case TaxObligationKind.custom:
      return l.taxObligationCustom;
  }
}

/// Label for a derived state.
String taxStateLabel(AppLocalizations l, TaxObligationState state) {
  switch (state) {
    case TaxObligationState.dismissed:
      return l.taxStateDismissed;
    case TaxObligationState.completed:
      return l.taxStateCompleted;
    case TaxObligationState.undated:
      return l.taxStateUndated;
    case TaxObligationState.overdue:
      return l.taxStateOverdue;
    case TaxObligationState.dueToday:
      return l.taxStateDueToday;
    case TaxObligationState.upcoming:
      return l.taxStateUpcoming;
  }
}

/// Label for the "where did this date come from" badge.
String taxDueDateSourceLabel(AppLocalizations l, TaxDueDateSource source) {
  switch (source) {
    case TaxDueDateSource.catalog:
      return l.taxDetailSourceCatalog;
    case TaxDueDateSource.override:
      return l.taxDetailSourceOverride;
    case TaxDueDateSource.user:
      return l.taxDetailSourceUser;
  }
}

/// The wizard's question text.
String taxWizardQuestion(AppLocalizations l, TaxWizardStep step) {
  switch (step) {
    case TaxWizardStep.legalForm:
      return l.taxWizardQuestionLegalForm;
    case TaxWizardStep.vatLiability:
      return l.taxWizardQuestionVat;
    case TaxWizardStep.withholdingLiability:
      return l.taxWizardQuestionWithholding;
    case TaxWizardStep.employsStaff:
      return l.taxWizardQuestionEmploysStaff;
    case TaxWizardStep.bagkurInsured:
      return l.taxWizardQuestionBagkur;
    case TaxWizardStep.usesELedger:
      return l.taxWizardQuestionELedger;
    case TaxWizardStep.ownsVehicle:
      return l.taxWizardQuestionVehicle;
    case TaxWizardStep.ownsRealEstate:
      return l.taxWizardQuestionRealEstate;
  }
}

/// Label for a legal form option.
String taxLegalFormLabel(AppLocalizations l, TaxpayerLegalForm form) {
  switch (form) {
    case TaxpayerLegalForm.sahisSirketi:
      return l.taxLegalFormSahis;
    case TaxpayerLegalForm.limited:
      return l.taxLegalFormLimited;
    case TaxpayerLegalForm.anonim:
      return l.taxLegalFormAnonim;
    case TaxpayerLegalForm.serbestMeslek:
      return l.taxLegalFormSerbestMeslek;
    case TaxpayerLegalForm.basitUsul:
      return l.taxLegalFormBasitUsul;
    case TaxpayerLegalForm.diger:
      return l.taxLegalFormDiger;
    case TaxpayerLegalForm.unspecified:
      return l.taxLegalFormUnspecified;
  }
}

/// Label for a yes/no/unknown answer.
String taxAnswerLabel(AppLocalizations l, TaxpayerAnswer answer) {
  switch (answer) {
    case TaxpayerAnswer.yes:
      return l.taxAnswerYes;
    case TaxpayerAnswer.no:
      return l.taxAnswerNo;
    case TaxpayerAnswer.unknown:
      return l.taxAnswerUnknown;
  }
}

/// Label for a VAT liability option.
String taxVatLiabilityLabel(AppLocalizations l, VatLiability liability) {
  switch (liability) {
    case VatLiability.monthly:
      return l.taxFrequencyMonthly;
    case VatLiability.quarterly:
      return l.taxFrequencyQuarterly;
    case VatLiability.none:
      return l.taxFrequencyNone;
    case VatLiability.unknown:
      return l.taxAnswerUnknown;
  }
}

/// Label for a withholding liability option.
String taxWithholdingLabel(AppLocalizations l, WithholdingLiability value) {
  switch (value) {
    case WithholdingLiability.monthly:
      return l.taxFrequencyMonthly;
    case WithholdingLiability.quarterly:
      return l.taxFrequencyQuarterly;
    case WithholdingLiability.none:
      return l.taxFrequencyNone;
    case WithholdingLiability.unknown:
      return l.taxAnswerUnknown;
  }
}

/// Label for the amount's source. There is no "calculated" case, because the
/// enum has no such value — SmartSpend does not work out tax.
String taxAmountSourceLabel(AppLocalizations l, TaxAmountSource source) {
  switch (source) {
    case TaxAmountSource.accountant:
      return l.taxDetailAmountSourceAccountant;
    case TaxAmountSource.user:
      return l.taxDetailAmountSourceUser;
    case TaxAmountSource.unknown:
      return l.taxAnswerUnknown;
  }
}
