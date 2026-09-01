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
