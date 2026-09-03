import 'package:equatable/equatable.dart';

import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';

/// One row of the tax calendar, as a screen needs it.
///
/// Joins three things the stored row does not carry on its own: the catalog's
/// knowledge of which steps this obligation even has, the l10n key for its
/// name, and whether its dates can be stated or only hedged.
///
/// [hasDeclarationStep] and [hasPaymentStep] are the load-bearing pair. Without
/// them "not filed yet" and "there is nothing to file" are indistinguishable —
/// Bağ-Kur's `declaredAt` is null forever — and the item could never reach
/// [TaxObligationState.completed].
class TaxCalendarItem extends Equatable {
  const TaxCalendarItem({
    required this.id,
    required this.kind,
    required this.nameL10nKey,
    required this.periodKind,
    required this.periodStart,
    required this.periodEnd,
    required this.installmentIndex,
    required this.dueDateSource,
    required this.amountSource,
    required this.hasDeclarationStep,
    required this.hasPaymentStep,
    required this.isConditional,
    required this.needsDateWarning,
    required this.isUserDefined,
    this.title,
    this.declarationDueDate,
    this.paymentDueDate,
    this.amountMinor,
    this.declaredAt,
    this.paidAt,
    this.dismissedAt,
    this.note,
    this.dueDateOverrideReason,
  });

  /// Local Drift row id.
  final int id;

  /// Which obligation this is.
  final TaxObligationKind kind;

  /// ARB key for the display name. User-defined items carry [title] instead.
  final String nameL10nKey;

  /// The user's own name for an item they created.
  final String? title;

  /// How often this recurs.
  final TaxPeriodKind periodKind;

  /// The period covered, UTC midnight dates.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// 0 for a single payment; 1, 2, … for installments.
  final int installmentIndex;

  /// Filing deadline, or null where there is no filing step or no confirmed
  /// rule. [hasDeclarationStep] separates the two.
  final DateTime? declarationDueDate;

  /// Payment deadline, under the same conditions.
  final DateTime? paymentDueDate;

  /// Where the dates came from — shown as a badge.
  ///
  /// [TaxDueDateSource.override] means *at least one* of the two dates was
  /// replaced by a published correction; an extension often moves the filing
  /// deadline and leaves the payment one alone. [dueDateOverrideReason] is
  /// what tells the user which, and on whose authority.
  final TaxDueDateSource dueDateSource;

  /// Why the date moved, when it moved because of a published override —
  /// a circular number, typically. Null for every other source.
  ///
  /// Not decoration. A date that changes with no stated reason is
  /// indistinguishable, from the user's side, from the app being wrong, and
  /// they have no way to check it against GİB without this.
  final String? dueDateOverrideReason;

  /// Whether this obligation is filed at all.
  final bool hasDeclarationStep;

  /// Whether anything is paid.
  final bool hasPaymentStep;

  /// True where the obligation only exists in periods that had a qualifying
  /// transaction (KDV-2). The card asks rather than asserts.
  final bool isConditional;

  /// True where the dates must be hedged rather than stated: the catalog rule
  /// is unverified, or no holiday list exists for that year so the deadline
  /// could not be moved off a weekend.
  ///
  /// True for every item today, which is why the card treats it as the normal
  /// case rather than as an exception.
  final bool needsDateWarning;

  /// Amount in the smallest currency unit, when a person has said.
  final int? amountMinor;

  /// Who said it. Never "the app worked it out" — that value does not exist.
  final TaxAmountSource amountSource;

  /// When the user marked it filed.
  final DateTime? declaredAt;

  /// When the user marked it paid.
  final DateTime? paidAt;

  /// When the user said it does not apply to them.
  final DateTime? dismissedAt;

  /// The user's note.
  final String? note;

  /// True for items the user added themselves.
  final bool isUserDefined;

  /// The state as of [today]. Derived on every read, never stored.
  TaxObligationState stateAt(DateTime today) => deriveTaxObligationState(
        today: today,
        hasDeclarationStep: hasDeclarationStep,
        hasPaymentStep: hasPaymentStep,
        declarationDueDate: declarationDueDate,
        paymentDueDate: paymentDueDate,
        declaredAt: declaredAt,
        paidAt: paidAt,
        dismissedAt: dismissedAt,
      );

  /// The earliest deadline still outstanding, for sorting and for the card's
  /// headline date. Null when nothing is known or nothing is left to do.
  DateTime? get nextDueDate {
    final List<DateTime> dates = <DateTime>[
      if (hasDeclarationStep &&
          declaredAt == null &&
          declarationDueDate != null)
        declarationDueDate!,
      if (hasPaymentStep && paidAt == null && paymentDueDate != null)
        paymentDueDate!,
    ]..sort();
    return dates.isEmpty ? null : dates.first;
  }

  /// Whether either deadline is known at all.
  bool get hasAnyDate =>
      declarationDueDate != null || paymentDueDate != null;

  @override
  List<Object?> get props => <Object?>[
        id,
        kind,
        nameL10nKey,
        title,
        periodKind,
        periodStart,
        periodEnd,
        installmentIndex,
        declarationDueDate,
        paymentDueDate,
        dueDateSource,
        hasDeclarationStep,
        hasPaymentStep,
        isConditional,
        needsDateWarning,
        amountMinor,
        amountSource,
        declaredAt,
        paidAt,
        dismissedAt,
        note,
        isUserDefined,
        dueDateOverrideReason,
      ];
}
