/// The value types a generated calendar item carries beyond the catalog.
///
/// The catalog says what an obligation *is*; these say what has happened to
/// one instance of it — whether it was filed, whether it was paid, what it
/// cost and who says so.
library;

/// Where a calendar item's dates came from.
///
/// Shown to the user as a badge, so it is not merely bookkeeping: an item
/// dated from a GİB circular and one dated from our own catalog deserve
/// different amounts of trust, and the badge is how the user can tell.
enum TaxDueDateSource {
  /// Resolved from the market catalog's rule.
  catalog('catalog'),

  /// Replaced by a server-side override — the channel GİB's filing extensions
  /// arrive through, since a date frozen into a binary is sometimes wrong.
  override('override'),

  /// Entered by the user, on their own item or over a generated one.
  user('user');

  const TaxDueDateSource(this.wireValue);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// Parses a persisted value; unrecognised reads as [catalog].
  static TaxDueDateSource fromWireValue(String? value) {
    for (final TaxDueDateSource source in TaxDueDateSource.values) {
      if (source.wireValue == value) {
        return source;
      }
    }
    return TaxDueDateSource.catalog;
  }
}

/// Who says what an obligation costs.
///
/// 🚨 There is deliberately no `computed` value, and a test pins its absence.
/// SmartSpend does not calculate tax. It has no line-item VAT breakdown until
/// 1.6.0, no knowledge of the user's deductions, and no licence to practise
/// accountancy; a number this app produced would be read as an amount to pay.
/// Every amount here was typed by a person — the accountant or the user — and
/// the enum is what makes "the app worked it out" unrepresentable rather than
/// merely discouraged.
enum TaxAmountSource {
  /// The accountant told the user this figure.
  accountant('accountant'),

  /// The user entered it themselves.
  user('user'),

  /// No amount, or no idea where the one that is here came from.
  unknown('unknown');

  const TaxAmountSource(this.wireValue);

  /// Stable persisted identifier. Never rename.
  final String wireValue;

  /// Parses a persisted value; unrecognised reads as [unknown].
  ///
  /// Note what this does to a hypothetical future `computed`: it reads back as
  /// [unknown] rather than crashing, so even a row written by a build that
  /// broke the rule cannot present a calculated figure as authoritative.
  static TaxAmountSource fromWireValue(String? value) {
    for (final TaxAmountSource source in TaxAmountSource.values) {
      if (source.wireValue == value) {
        return source;
      }
    }
    return TaxAmountSource.unknown;
  }
}

/// What a calendar item currently is, as far as this device can tell.
///
/// 🚨 Derived, never stored. It is a function of the deadlines and today's
/// date, and both are already on the row. Written down, it would be computed
/// by whichever device wrote last — including one with a wrong clock, or one
/// that had not synced in a week — and last-write-wins would then hand that
/// verdict to every other device. A wrong clock here costs one device a wrong
/// badge until it is corrected; stored, it would cost the user a false "you
/// missed this".
enum TaxObligationState {
  /// The user said this does not apply to them.
  dismissed,

  /// Every step that exists has been marked.
  completed,

  /// No deadline is known — the catalog rule is not confirmed. The item is
  /// real, the date is not, and the UI says exactly that.
  undated,

  /// A step that has not been marked was due before today.
  overdue,

  /// A step that has not been marked is due today.
  dueToday,

  /// Still ahead.
  upcoming,
}

/// Derives the state of one item.
///
/// [today] is a UTC calendar date, passed in rather than read from a clock:
/// the whole function is then testable by moving a variable, which is how the
/// "device clock is wrong" cases get covered at all.
///
/// [hasDeclarationStep] and [hasPaymentStep] come from the catalog. They are
/// needed because "not filed yet" and "there is nothing to file" look
/// identical on the row — Bağ-Kur's declaredAt is null forever, and without
/// this it could never reach [TaxObligationState.completed].
TaxObligationState deriveTaxObligationState({
  required DateTime today,
  required bool hasDeclarationStep,
  required bool hasPaymentStep,
  DateTime? declarationDueDate,
  DateTime? paymentDueDate,
  DateTime? declaredAt,
  DateTime? paidAt,
  DateTime? dismissedAt,
}) {
  if (dismissedAt != null) {
    return TaxObligationState.dismissed;
  }

  final bool declarationOutstanding = hasDeclarationStep && declaredAt == null;
  final bool paymentOutstanding = hasPaymentStep && paidAt == null;
  if (!declarationOutstanding && !paymentOutstanding) {
    return TaxObligationState.completed;
  }

  final DateTime day = DateTime.utc(today.year, today.month, today.day);
  final List<DateTime> outstanding = <DateTime>[
    if (declarationOutstanding && declarationDueDate != null)
      declarationDueDate,
    if (paymentOutstanding && paymentDueDate != null) paymentDueDate,
  ];
  if (outstanding.isEmpty) {
    // Something is still to do and nothing says by when. Saying "upcoming"
    // would imply we know it has not passed.
    return TaxObligationState.undated;
  }

  outstanding.sort();
  final DateTime earliest = DateTime.utc(
    outstanding.first.year,
    outstanding.first.month,
    outstanding.first.day,
  );
  if (earliest.isBefore(day)) {
    return TaxObligationState.overdue;
  }
  if (earliest.isAtSameMomentAs(day)) {
    return TaxObligationState.dueToday;
  }
  return TaxObligationState.upcoming;
}
