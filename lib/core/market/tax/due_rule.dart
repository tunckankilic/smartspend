/// How a tax deadline is expressed before it becomes a date.
///
/// ## Why a rule and not a date
///
/// A deadline like "the 26th of the month following the period" survives leap
/// years, quarter boundaries and the user changing their period type. A stored
/// date does not. The catalog therefore carries rules; [DueRule.resolveFrom]
/// turns one into a calendar date at the moment a calendar item is generated.
///
/// ## Why nothing here is confirmed yet
///
/// A wrong deadline in a tax app is worse than a missing one: it is believed.
/// So the numbers are not the default state of this type — [UnverifiedDueDate]
/// is, and it *has no day and no offset field to hold a guess in*. Confirming
/// a rule means changing its variant, which is a visible diff and cannot be
/// done by accident. See `docs/internal/pivot/KATALOG_TEYIT.md` for the
/// worksheet that has to be filled from a primary source before any
/// [ConfirmedDueDates] appears in the catalog.
library;

/// Which day of a month a deadline lands on.
sealed class DueDay {
  const DueDay();

  /// The day number within [year]/[month], clamped to that month's length.
  int resolve(int year, int month);
}

/// A fixed day number — "the 26th".
///
/// Clamps: a rule saying "the 31st" resolves to the 30th in a 30-day month and
/// to the 28th or 29th in February, which is how such rules are read.
final class FixedDueDay extends DueDay {
  const FixedDueDay(this.day)
      : assert(day >= 1 && day <= 31, 'day of month out of range');

  /// 1–31.
  final int day;

  @override
  int resolve(int year, int month) {
    final int last = _lastDayOfMonth(year, month);
    return day <= last ? day : last;
  }
}

/// "The last day of the month", whatever its length.
final class LastDayOfMonth extends DueDay {
  const LastDayOfMonth();

  @override
  int resolve(int year, int month) => _lastDayOfMonth(year, month);
}

int _lastDayOfMonth(int year, int month) =>
    DateTime.utc(year, month + 1, 0).day;

/// One confirmed deadline rule: an offset from the period's last month, plus a
/// day within the month it lands in.
///
/// `monthsAfterPeriodEnd: 1, day: FixedDueDay(26)` reads as "the 26th of the
/// month after the period ends".
final class DueRule {
  const DueRule({
    required this.monthsAfterPeriodEnd,
    required this.day,
  }) : assert(
          monthsAfterPeriodEnd >= 0,
          'a deadline cannot precede its period',
        );

  /// 0 = within the period's own final month.
  final int monthsAfterPeriodEnd;

  /// Where in that month the deadline falls.
  final DueDay day;

  /// The date this rule produces for a period ending in
  /// [periodEndYear]/[periodEndMonth] (1-based month).
  ///
  /// Returns a UTC midnight date. It is a *calendar* date, not an instant:
  /// turning it into a reminder time is the notification layer's job, and it
  /// has to do that in Europe/Istanbul rather than in the device zone.
  ///
  /// Deferral for weekends and public holidays is **not** applied here — that
  /// is the shifting engine (T5), which needs a holiday list this rule knows
  /// nothing about.
  DateTime resolveFrom(int periodEndYear, int periodEndMonth) {
    final int monthsFromYearStart = periodEndMonth + monthsAfterPeriodEnd - 1;
    final int year = periodEndYear + monthsFromYearStart ~/ 12;
    final int month = monthsFromYearStart % 12 + 1;
    return DateTime.utc(year, month, day.resolve(year, month));
  }
}

/// The state of one side (declaration or payment) of an obligation.
///
/// Three states, not two, and not a nullable [DueRule]: "this obligation has
/// no payment step" and "we have not confirmed the payment deadline yet" are
/// opposite facts, and a `null` cannot tell them apart. Roughly a third of the
/// catalog is missing one side or the other, so this distinction is load
/// bearing rather than defensive.
sealed class DueSchedule {
  const DueSchedule();
}

/// This obligation structurally has no such deadline.
///
/// Bağ-Kur has no declaration; Ba/Bs forms and the e-ledger berat have no
/// payment. The UI shows nothing rather than an empty field.
final class NoDueDate extends DueSchedule {
  const NoDueDate(this.reason);

  /// Why the step does not exist, for the developer reading the catalog.
  final String reason;
}

/// The deadline exists and its rule is not confirmed yet.
///
/// Carries no numbers on purpose. The generator turns this into an item with
/// no date and a "confirm with your accountant" marker — visibly incomplete,
/// which is the honest failure mode.
final class UnverifiedDueDate extends DueSchedule {
  const UnverifiedDueDate(this.note);

  /// What has to be looked up, in the words of the worksheet.
  final String note;
}

/// A confirmed rule, or several when the obligation is paid in installments.
///
/// [source] names where the numbers were read from and when. It is developer
/// documentation, not a user-facing citation.
final class ConfirmedDueDates extends DueSchedule {
  const ConfirmedDueDates({
    required this.installments,
    required this.source,
  });

  /// One entry per installment, in calendar order. Usually one.
  final List<DueRule> installments;

  /// Primary source and date of confirmation.
  final String source;
}
