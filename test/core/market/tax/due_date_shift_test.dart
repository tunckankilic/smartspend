import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/due_date_shift.dart';

/// A filled year, built in the test rather than shipped in the app.
///
/// The dates below are fixtures with no claim to being the real Turkish
/// calendar — that list has to be verified per year from a primary source,
/// which is exactly why the shipped registry is empty.
TrHolidayCalendar _calendar({
  Set<DateTime> holidays = const <DateTime>{},
  FiscalBreak? fiscalBreak,
  bool isComplete = true,
}) =>
    TrHolidayCalendar(
      year: 2026,
      nonWorkingDays: holidays,
      fiscalBreak: fiscalBreak,
      isComplete: isComplete,
    );

Map<int, TrHolidayCalendar> _registry(TrHolidayCalendar calendar) =>
    <int, TrHolidayCalendar>{calendar.year: calendar};

void main() {
  group('with no calendar for the year', () {
    test('should return the legal date untouched', () {
      // 🚨 The rule the whole file exists for: break honestly. Shifting a
      // Saturday to a Monday that turns out to be the second day of Kurban
      // Bayramı is worse than not shifting — it looks authoritative and it
      // is wrong.
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 29), // a Saturday
        calendars: const <int, TrHolidayCalendar>{},
      );

      expect(shift.effective, DateTime.utc(2026, 8, 29));
      expect(shift.moved, isFalse);
      expect(shift.confidence, TaxDueDateConfidence.unavailable);
      expect(shift.needsWarning, isTrue);
      expect(shift.reasons, isEmpty);
    });

    test('should be what the shipped registry does today', () {
      // Every year is unfilled, so every date comes back raw and flagged.
      expect(trHolidayCalendars, isEmpty);

      final TaxDueDateShift shift = shiftDueDate(DateTime.utc(2026, 8, 29));

      expect(shift.confidence, TaxDueDateConfidence.unavailable);
      expect(shift.effective, shift.original);
    });
  });

  group('weekends', () {
    test('should move a Saturday to the Monday', () {
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 29),
        calendars: _registry(_calendar()),
      );

      expect(DateTime.utc(2026, 8, 29).weekday, DateTime.saturday);
      expect(shift.effective, DateTime.utc(2026, 8, 31));
      expect(shift.reasons, <TaxDueDateShiftReason>[
        TaxDueDateShiftReason.weekend,
      ]);
    });

    test('should move a Sunday by one day', () {
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 30),
        calendars: _registry(_calendar()),
      );

      expect(shift.effective, DateTime.utc(2026, 8, 31));
    });

    test('should leave a working day alone', () {
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 28),
        calendars: _registry(_calendar()),
      );

      expect(shift.moved, isFalse);
      expect(shift.reasons, isEmpty);
      expect(shift.confidence, TaxDueDateConfidence.complete);
      expect(shift.needsWarning, isFalse);
    });
  });

  group('holidays', () {
    test('should step over a listed holiday', () {
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 28),
        calendars: _registry(
          _calendar(holidays: <DateTime>{DateTime.utc(2026, 8, 28)}),
        ),
      );

      expect(shift.effective, DateTime.utc(2026, 8, 31));
      expect(shift.reasons, containsAll(<TaxDueDateShiftReason>[
        TaxDueDateShiftReason.publicHoliday,
        TaxDueDateShiftReason.weekend,
      ]));
    });

    test('should walk over a holiday that abuts a weekend', () {
      // A three-day religious holiday running into a Saturday is the normal
      // case, not an edge one — which is why this walks day by day instead of
      // computing an offset.
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 26),
        calendars: _registry(
          _calendar(
            holidays: <DateTime>{
              DateTime.utc(2026, 8, 26),
              DateTime.utc(2026, 8, 27),
              DateTime.utc(2026, 8, 28),
            },
          ),
        ),
      );

      expect(shift.effective, DateTime.utc(2026, 8, 31));
    });

    test('should give up rather than loop on a malformed calendar', () {
      // A calendar marking a whole month non-working is a data bug, not a
      // reason to hang the calendar screen.
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8),
        calendars: _registry(
          _calendar(
            holidays: <DateTime>{
              for (int day = 1; day <= 31; day++) DateTime.utc(2026, 8, day),
              for (int day = 1; day <= 30; day++) DateTime.utc(2026, 9, day),
            },
          ),
        ),
      );

      expect(shift.effective.isAfter(DateTime.utc(2026, 8)), isTrue);
    });
  });

  group('mali tatil', () {
    test('should carry a deadline past the end of the break', () {
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 7, 10),
        calendars: _registry(
          _calendar(
            fiscalBreak: FiscalBreak(
              start: DateTime.utc(2026, 7),
              end: DateTime.utc(2026, 7, 20),
              daysAfterEnd: 7,
            ),
          ),
        ),
      );

      expect(shift.effective, DateTime.utc(2026, 7, 27));
      expect(
        shift.reasons.first,
        TaxDueDateShiftReason.fiscalBreak,
      );
    });

    test('should defer the date the break produced, not the original', () {
      // Order matters: applying the weekend rule first would land back inside
      // the break.
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 7, 10),
        calendars: _registry(
          _calendar(
            fiscalBreak: FiscalBreak(
              start: DateTime.utc(2026, 7),
              end: DateTime.utc(2026, 7, 20),
              daysAfterEnd: 5, // lands on Saturday 25 July 2026
            ),
          ),
        ),
      );

      expect(DateTime.utc(2026, 7, 25).weekday, DateTime.saturday);
      expect(shift.effective, DateTime.utc(2026, 7, 27));
      expect(shift.reasons, <TaxDueDateShiftReason>[
        TaxDueDateShiftReason.fiscalBreak,
        TaxDueDateShiftReason.weekend,
      ]);
    });

    test('should leave a deadline outside the break alone', () {
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 7, 28),
        calendars: _registry(
          _calendar(
            fiscalBreak: FiscalBreak(
              start: DateTime.utc(2026, 7),
              end: DateTime.utc(2026, 7, 20),
              daysAfterEnd: 7,
            ),
          ),
        ),
      );

      expect(shift.moved, isFalse);
    });
  });

  group('an incomplete list', () {
    test('should still compute, but never claim to be authoritative', () {
      // A year with its fixed-date holidays filled in and its religious ones
      // still missing. The answer is better than nothing and worse than a
      // fact, and the UI has to be told which.
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 29),
        calendars: _registry(_calendar(isComplete: false)),
      );

      expect(shift.effective, DateTime.utc(2026, 8, 31));
      expect(shift.confidence, TaxDueDateConfidence.partial);
      expect(shift.needsWarning, isTrue);
    });
  });

  group('inputs', () {
    test('should normalise a date carrying a time of day', () {
      final TaxDueDateShift shift = shiftDueDate(
        DateTime.utc(2026, 8, 28, 17, 42),
        calendars: _registry(_calendar()),
      );

      expect(shift.original, DateTime.utc(2026, 8, 28));
      expect(shift.effective, DateTime.utc(2026, 8, 28));
    });
  });
}
