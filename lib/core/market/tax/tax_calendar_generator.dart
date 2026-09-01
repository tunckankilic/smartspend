/// Profile × catalog → calendar items. Pure: no I/O, no clock, no database.
///
/// Everything the generator needs is an argument, which is what makes the
/// awkward cases — a leap February, a quarter that crosses a year end, a
/// profile with three questions answered — ordinary unit tests rather than
/// something you can only observe by changing the device date.
///
/// ## What it refuses to do
///
/// It never invents a date. An obligation whose catalog rule is unconfirmed
/// comes out with null deadlines and a [TaxCalendarGap] saying why; an
/// obligation whose recurrence depends on a question the user skipped is not
/// generated at all, and is reported as a gap instead. Both are visible
/// incompleteness. The alternative — defaulting to the commoner option — puts
/// deadlines in front of someone who never said they had them.
library;

import 'package:smartspend/core/market/tax/due_rule.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_spec.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

/// One period of one obligation, as the generator produces it.
final class GeneratedObligation {
  const GeneratedObligation({
    required this.kind,
    required this.generationKey,
    required this.periodKind,
    required this.periodStart,
    required this.periodEnd,
    required this.installmentIndex,
    required this.applicability,
    required this.declarationDueDate,
    required this.paymentDueDate,
    required this.isConditional,
    required this.hasUnverifiedRule,
  });

  /// Which obligation this is.
  final TaxObligationKind kind;

  /// `kind|periodStart|installmentIndex` — the identity two devices agree on.
  final String generationKey;

  /// The recurrence this period came from.
  final TaxPeriodKind periodKind;

  /// First and last day of the period, UTC midnight.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// 0 for a single payment; 1, 2, … for installments.
  final int installmentIndex;

  /// [TaxObligationApplicability.applies] or
  /// [TaxObligationApplicability.unknown] — items that do not apply are never
  /// generated.
  final TaxObligationApplicability applicability;

  /// Filing deadline, or null where there is no filing step or no confirmed
  /// rule. [hasUnverifiedRule] tells the two apart.
  final DateTime? declarationDueDate;

  /// Payment deadline, under the same conditions.
  final DateTime? paymentDueDate;

  /// True where the obligation only exists in periods that had a qualifying
  /// transaction (KDV-2). The UI asks rather than asserts.
  final bool isConditional;

  /// True where at least one of this item's deadlines is missing because the
  /// catalog rule has not been verified — as opposed to not existing.
  final bool hasUnverifiedRule;
}

/// Why something the user might have expected is not in their calendar.
final class TaxCalendarGap {
  const TaxCalendarGap({required this.kind, required this.reason});

  /// The obligation that could not be generated.
  final TaxObligationKind kind;

  /// Which of the two honest failures this is.
  final TaxCalendarGapReason reason;
}

/// The two ways generation declines to produce an item.
enum TaxCalendarGapReason {
  /// The profile does not say how often this recurs — the user skipped the
  /// question. Guessing would manufacture eleven deadlines a year.
  recurrenceUnknown,

  /// The obligation might apply, but its recurrence question is unanswered
  /// *and* its applicability is unknown, so there is nothing to place.
  applicabilityUnknown,
}

/// What one generation run produced.
final class TaxCalendar {
  const TaxCalendar({required this.obligations, required this.gaps});

  /// The items, in period order.
  final List<GeneratedObligation> obligations;

  /// What could not be generated, and why. Surfaced to the user as "finish
  /// your profile to see these" rather than silently omitted.
  final List<TaxCalendarGap> gaps;

  /// Whether anything at all is missing or undated.
  bool get isPartial =>
      gaps.isNotEmpty ||
      obligations.any((GeneratedObligation o) => o.hasUnverifiedRule);
}

/// Generates the calendar for [profile] over every period overlapping
/// [rangeStart]..[rangeEnd].
///
/// The range is expressed in *periods*, not deadlines: a monthly obligation's
/// deadline falls after its period ends, so a caller listing "deadlines in
/// October" asks for periods from roughly September. Keeping the generator on
/// period boundaries makes its output stable — the same window always produces
/// the same items — and leaves the widening to the caller that knows which
/// question it is answering.
///
/// [shiftDueDate] is the deferral hook: weekends, public holidays and the mali
/// tatil move a deadline to the next working day, and the calendar that knows
/// about those is not this function's business. When it is null, resolved
/// dates come out unshifted.
TaxCalendar generateTaxCalendar({
  required TaxpayerProfile profile,
  required List<TaxObligationSpec> catalog,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  DateTime Function(DateTime)? shiftDueDate,
}) {
  final List<GeneratedObligation> obligations = <GeneratedObligation>[];
  final List<TaxCalendarGap> gaps = <TaxCalendarGap>[];

  for (final TaxObligationSpec spec in catalog) {
    if (spec.isUserDefined) {
      continue;
    }

    final TaxObligationApplicability applicability =
        spec.eligibility.evaluate(profile);
    if (applicability == TaxObligationApplicability.doesNotApply) {
      continue;
    }

    final TaxPeriodKind? periodKind = spec.resolvePeriodKind(profile);
    if (periodKind == null || periodKind == TaxPeriodKind.oneOff) {
      // The user skipped the question that decides how often this recurs.
      // Reported, not guessed: defaulting to monthly would put eleven
      // invented deadlines a year in front of someone who never said they
      // file anything.
      gaps.add(
        TaxCalendarGap(
          kind: spec.kind,
          reason: applicability == TaxObligationApplicability.unknown
              ? TaxCalendarGapReason.applicabilityUnknown
              : TaxCalendarGapReason.recurrenceUnknown,
        ),
      );
      continue;
    }

    for (final _Period period
        in _periodsOverlapping(periodKind, rangeStart, rangeEnd)) {
      obligations.addAll(
        _itemsForPeriod(
          spec: spec,
          periodKind: periodKind,
          period: period,
          applicability: applicability,
          shiftDueDate: shiftDueDate,
        ),
      );
    }
  }

  obligations.sort((GeneratedObligation a, GeneratedObligation b) {
    final int byPeriod = a.periodStart.compareTo(b.periodStart);
    if (byPeriod != 0) {
      return byPeriod;
    }
    final int byKind = a.kind.wireValue.compareTo(b.kind.wireValue);
    return byKind != 0
        ? byKind
        : a.installmentIndex.compareTo(b.installmentIndex);
  });

  return TaxCalendar(obligations: obligations, gaps: gaps);
}

/// Builds the rows for one period.
///
/// The row count follows the payment installments, because that is the only
/// side that can repeat within a period: an obligation paid in two
/// installments produces two rows, and the filing deadline — of which there is
/// only ever one — attaches to the first.
List<GeneratedObligation> _itemsForPeriod({
  required TaxObligationSpec spec,
  required TaxPeriodKind periodKind,
  required _Period period,
  required TaxObligationApplicability applicability,
  required DateTime Function(DateTime)? shiftDueDate,
}) {
  final DueSchedule declaration = spec.declaration;
  final DueSchedule payment = spec.payment;

  final List<DueRule?> paymentRules = payment is ConfirmedDueDates
      ? payment.installments
      : <DueRule?>[null];

  final DateTime? declarationDate = declaration is ConfirmedDueDates &&
          declaration.installments.isNotEmpty
      ? _resolve(declaration.installments.first, period, shiftDueDate)
      : null;

  final bool unverified =
      declaration is UnverifiedDueDate || payment is UnverifiedDueDate;

  return <GeneratedObligation>[
    for (int i = 0; i < paymentRules.length; i++)
      GeneratedObligation(
        kind: spec.kind,
        generationKey: taxGenerationKey(
          kind: spec.kind,
          periodStart: period.start,
          installmentIndex: paymentRules.length == 1 ? 0 : i + 1,
        ),
        periodKind: periodKind,
        periodStart: period.start,
        periodEnd: period.end,
        installmentIndex: paymentRules.length == 1 ? 0 : i + 1,
        applicability: applicability,
        // One filing, however many payments: it belongs to the first row.
        declarationDueDate: i == 0 ? declarationDate : null,
        paymentDueDate: paymentRules[i] == null
            ? null
            : _resolve(paymentRules[i]!, period, shiftDueDate),
        isConditional: spec.occursOnlyWhenTransactionsExist,
        hasUnverifiedRule: unverified,
      ),
  ];
}

DateTime _resolve(
  DueRule rule,
  _Period period,
  DateTime Function(DateTime)? shiftDueDate,
) {
  final DateTime raw = rule.resolveFrom(period.end.year, period.end.month);
  return shiftDueDate == null ? raw : shiftDueDate(raw);
}

/// The identity of a generated item, shared by every device that generates it.
///
/// Deterministic by construction: same kind, same period, same installment,
/// same string. That is what stops a phone and a tablet from each pushing
/// their own copy of August's return.
String taxGenerationKey({
  required TaxObligationKind kind,
  required DateTime periodStart,
  required int installmentIndex,
}) {
  final String day = periodStart.toUtc().toIso8601String().split('T').first;
  return '${kind.wireValue}|$day|$installmentIndex';
}

final class _Period {
  const _Period(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

/// Every period of [kind] that overlaps [rangeStart]..[rangeEnd].
///
/// Periods are aligned to the calendar — quarters start in January, April,
/// July and October — rather than to the range, so the same period has the
/// same boundaries no matter which window asked for it.
List<_Period> _periodsOverlapping(
  TaxPeriodKind kind,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final DateTime from = DateTime.utc(rangeStart.year, rangeStart.month, 1);
  final DateTime to = rangeEnd.toUtc();
  final List<_Period> periods = <_Period>[];

  DateTime cursor = switch (kind) {
    TaxPeriodKind.monthly => from,
    TaxPeriodKind.quarterly =>
      DateTime.utc(from.year, from.month - (from.month - 1) % 3, 1),
    TaxPeriodKind.annual => DateTime.utc(from.year, 1, 1),
    TaxPeriodKind.oneOff => from,
  };

  if (kind == TaxPeriodKind.oneOff) {
    return periods;
  }

  // A guard rather than a policy: the loop is bounded by the range, and this
  // only stops a caller's decade-wide window from generating silently forever.
  const int maxPeriods = 400;
  while (cursor.isBefore(to) || cursor.isAtSameMomentAs(to)) {
    final DateTime end = DateTime.utc(
      cursor.year,
      cursor.month + kind.monthsPerPeriod,
      0,
    );
    periods.add(_Period(cursor, end));
    if (periods.length >= maxPeriods) {
      break;
    }
    cursor = DateTime.utc(cursor.year, cursor.month + kind.monthsPerPeriod, 1);
  }
  return periods;
}
