/// Cadence on which a budget resets.
///
/// Persisted as the lowercase enum name in `budgets.period`. Sprint 6
/// initially exposes weekly + monthly to the user; yearly is reserved
/// for future "annual savings goal" budgets that fall out naturally
/// from the same window calculator.
enum BudgetPeriod {
  weekly,
  monthly,
  yearly;

  /// Decode a textual column value into a typed enum.
  /// Returns `null` for unknown / empty values so the data layer can
  /// fall back to a safe default.
  static BudgetPeriod? fromName(String? value) {
    if (value == null) return null;
    for (final BudgetPeriod p in BudgetPeriod.values) {
      if (p.name == value) return p;
    }
    return null;
  }
}
