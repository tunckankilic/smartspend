/// Moving a legal deadline onto the day it can actually be met.
///
/// A Turkish filing deadline that lands on a Saturday, a public holiday or
/// inside the mali tatil does not stay there. Getting that shift right needs
/// three kinds of knowledge, and they are not equally knowable:
///
///   * **Weekends** are structural. No data needed.
///   * **Fixed-date national holidays** repeat on the same Gregorian date.
///   * **Religious holidays** (Ramazan and Kurban Bayramı) follow the lunar
///     calendar, shift about eleven days a year, and their exact Gregorian
///     dates — along with the half-days around them — are set per year. There
///     is no formula this app can carry.
///
/// ## The rule this file exists to enforce
///
/// **When the year's list is missing, break honestly.** No calendar for a year
/// means the deadline comes back untouched, marked
/// [TaxDueDateConfidence.unavailable], and the UI shows the raw legal date
/// with a warning rather than a confident wrong one. Shifting a Saturday to a
/// Monday that turns out to be the second day of Kurban Bayramı is worse than
/// not shifting at all: it looks authoritative and it is wrong.
///
/// That is also why [trHolidayCalendars] ships **empty**. Every date in it
/// would have to be verified per year against a primary source, exactly like
/// the deadline rules in `tr_tax_catalog.dart`, and this file will not carry
/// numbers nobody has checked. Filling it is a data task with a worksheet, not
/// a coding task.
library;

/// The mali tatil — a statutory break during which deadlines do not run.
///
/// Modelled as data rather than as a hardcoded window: the dates are set by
/// law and could change, and the extension rule is a separate question from
/// when the break falls.
final class FiscalBreak {
  const FiscalBreak({
    required this.start,
    required this.end,
    required this.daysAfterEnd,
  });

  /// First and last day of the break, inclusive, UTC midnight.
  final DateTime start;
  final DateTime end;

  /// How many days after [end] a deadline that fell inside the break lands on,
  /// before weekend and holiday deferral is applied to *that* date in turn.
  final int daysAfterEnd;

  /// Whether [date] falls inside the break.
  bool contains(DateTime date) {
    final DateTime day = DateTime.utc(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

/// One year's non-working days.
///
/// [isComplete] is the honest flag: a calendar can be present and still be
/// missing the religious holidays, and a partial calendar must not be
/// presented as authoritative.
final class TrHolidayCalendar {
  const TrHolidayCalendar({
    required this.year,
    required this.nonWorkingDays,
    required this.isComplete,
    this.fiscalBreak,
  });

  /// The Gregorian year this describes.
  final int year;

  /// Every non-working day in the year, as UTC midnight dates.
  final Set<DateTime> nonWorkingDays;

  /// The mali tatil, when the year has one.
  final FiscalBreak? fiscalBreak;

  /// Whether this year's religious holidays have been filled in and verified.
  ///
  /// False means "this list is known to be missing days" — the result is still
  /// computed, but it is reported as [TaxDueDateConfidence.partial] so the UI
  /// can hedge rather than assert.
  final bool isComplete;

  /// Whether [date] is a non-working day: a weekend, or a listed holiday.
  bool isNonWorkingDay(DateTime date) {
    final DateTime day = DateTime.utc(date.year, date.month, date.day);
    return day.weekday == DateTime.saturday ||
        day.weekday == DateTime.sunday ||
        nonWorkingDays.contains(day);
  }
}

/// How much the shifted date can be trusted.
enum TaxDueDateConfidence {
  /// The year's calendar is present and verified complete.
  complete,

  /// The calendar is present but known to be missing days — typically the
  /// religious holidays. Shown with a hedge.
  partial,

  /// No calendar for that year. The date was **not** shifted; the raw legal
  /// date is returned and the UI must warn.
  unavailable,
}

/// Why a date moved.
enum TaxDueDateShiftReason {
  /// It landed on a Saturday or Sunday.
  weekend,

  /// It landed on a listed public holiday.
  publicHoliday,

  /// It landed inside the mali tatil.
  fiscalBreak,
}

/// The outcome of deferring one deadline.
final class TaxDueDateShift {
  const TaxDueDateShift({
    required this.original,
    required this.effective,
    required this.confidence,
    required this.reasons,
  });

  /// The legal date the catalog rule produced.
  final DateTime original;

  /// The date to show the user. Equal to [original] when nothing moved it —
  /// including when [confidence] is [TaxDueDateConfidence.unavailable], where
  /// it is equal because nothing *could* move it.
  final DateTime effective;

  /// How much [effective] can be trusted.
  final TaxDueDateConfidence confidence;

  /// Why it moved, in the order the rules were applied. Empty when it did not.
  final List<TaxDueDateShiftReason> reasons;

  /// Whether the date moved at all.
  bool get moved => !effective.isAtSameMomentAs(original);

  /// Whether the UI has to hedge this date rather than state it.
  ///
  /// True whenever the deferral could not be computed from a verified list —
  /// which is every date today, because no year's calendar is filled in.
  bool get needsWarning => confidence != TaxDueDateConfidence.complete;
}

/// Verified non-working-day calendars, by year.
///
/// 🚨 Deliberately empty. Filling a year means verifying, from a primary
/// source: the fixed-date national holidays, that year's Ramazan and Kurban
/// Bayramı days including the half-days, and the mali tatil window and its
/// extension rule. Until a year is filled, every deadline in it comes back
/// unshifted and flagged — which is the correct behaviour, not a stub.
///
/// See `docs/internal/pivot/KATALOG_TEYIT.md`.
const Map<int, TrHolidayCalendar> trHolidayCalendars =
    <int, TrHolidayCalendar>{};

/// Moves [dueDate] onto the first day it can actually be met.
///
/// The order matters. A deadline inside the mali tatil first moves to the end
/// of the break plus its extension, and only then is that new date pushed off
/// weekends and holidays — applying the two in the other order would land on a
/// date inside the break.
///
/// With no calendar for the year, returns [dueDate] untouched and
/// [TaxDueDateConfidence.unavailable]. That is the honest failure: the raw
/// legal date plus a warning, rather than a confident date that is wrong
/// because we did not know about a religious holiday.
TaxDueDateShift shiftDueDate(
  DateTime dueDate, {
  Map<int, TrHolidayCalendar> calendars = trHolidayCalendars,
}) {
  final DateTime original =
      DateTime.utc(dueDate.year, dueDate.month, dueDate.day);
  final TrHolidayCalendar? calendar = calendars[original.year];

  if (calendar == null) {
    return TaxDueDateShift(
      original: original,
      effective: original,
      confidence: TaxDueDateConfidence.unavailable,
      reasons: const <TaxDueDateShiftReason>[],
    );
  }

  final List<TaxDueDateShiftReason> reasons = <TaxDueDateShiftReason>[];
  DateTime candidate = original;

  final FiscalBreak? fiscalBreak = calendar.fiscalBreak;
  if (fiscalBreak != null && fiscalBreak.contains(candidate)) {
    reasons.add(TaxDueDateShiftReason.fiscalBreak);
    candidate = fiscalBreak.end.add(Duration(days: fiscalBreak.daysAfterEnd));
  }

  // Walking day by day rather than computing an offset: a holiday can abut a
  // weekend, and a break's end date can itself be a holiday. The bound is a
  // guard against a malformed calendar marking a whole month non-working, not
  // a policy — a real run takes a handful of steps.
  const int maxSteps = 30;
  for (int step = 0; step < maxSteps; step++) {
    if (!calendar.isNonWorkingDay(candidate)) {
      break;
    }
    final bool isWeekend = candidate.weekday == DateTime.saturday ||
        candidate.weekday == DateTime.sunday;
    final TaxDueDateShiftReason reason = isWeekend
        ? TaxDueDateShiftReason.weekend
        : TaxDueDateShiftReason.publicHoliday;
    if (!reasons.contains(reason)) {
      reasons.add(reason);
    }
    candidate = candidate.add(const Duration(days: 1));
  }

  return TaxDueDateShift(
    original: original,
    effective: candidate,
    confidence: calendar.isComplete
        ? TaxDueDateConfidence.complete
        : TaxDueDateConfidence.partial,
    reasons: reasons,
  );
}
