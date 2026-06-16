/// Recurrence cadence for a recurring expense.
///
/// Persisted as the lowercase enum name in the `expenses.recurring_period`
/// column. The Sprint 6 notification engine reads these to schedule the next
/// occurrence; Sprint 3 only writes/reads the value.
enum RecurringPeriod {
  weekly,
  monthly,
  yearly;

  /// Decode the textual column value back into a typed enum.
  /// Returns `null` for unknown / empty values.
  static RecurringPeriod? fromName(String? value) {
    if (value == null) return null;
    for (final RecurringPeriod p in RecurringPeriod.values) {
      if (p.name == value) return p;
    }
    return null;
  }
}
