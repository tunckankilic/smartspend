import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/due_rule.dart';

void main() {
  group('FixedDueDay', () {
    test('should return the day itself when the month is long enough', () {
      expect(const FixedDueDay(26).resolve(2026, 1), 26);
    });

    test('should clamp to the last day of a short month', () {
      expect(const FixedDueDay(31).resolve(2026, 4), 30);
      expect(const FixedDueDay(31).resolve(2026, 2), 28);
    });

    test('should clamp to 29 in February of a leap year', () {
      expect(const FixedDueDay(31).resolve(2028, 2), 29);
      expect(const FixedDueDay(30).resolve(2028, 2), 29);
    });
  });

  group('LastDayOfMonth', () {
    test('should follow the length of the month', () {
      expect(const LastDayOfMonth().resolve(2026, 1), 31);
      expect(const LastDayOfMonth().resolve(2026, 4), 30);
      expect(const LastDayOfMonth().resolve(2026, 2), 28);
      expect(const LastDayOfMonth().resolve(2028, 2), 29);
    });
  });

  group('DueRule.resolveFrom', () {
    test('should stay in the period month when the offset is zero', () {
      const DueRule rule = DueRule(
        monthsAfterPeriodEnd: 0,
        day: FixedDueDay(15),
      );

      expect(rule.resolveFrom(2026, 3), DateTime.utc(2026, 3, 15));
    });

    test('should move into the following month', () {
      const DueRule rule = DueRule(
        monthsAfterPeriodEnd: 1,
        day: FixedDueDay(26),
      );

      expect(rule.resolveFrom(2026, 3), DateTime.utc(2026, 4, 26));
    });

    test('should roll over the year end', () {
      const DueRule rule = DueRule(
        monthsAfterPeriodEnd: 1,
        day: FixedDueDay(26),
      );

      expect(rule.resolveFrom(2026, 12), DateTime.utc(2027, 1, 26));
    });

    test('should roll over more than a year', () {
      const DueRule rule = DueRule(
        monthsAfterPeriodEnd: 14,
        day: FixedDueDay(1),
      );

      expect(rule.resolveFrom(2026, 12), DateTime.utc(2028, 2, 1));
    });

    test('should clamp the day inside the month it lands in', () {
      const DueRule rule = DueRule(
        monthsAfterPeriodEnd: 1,
        day: FixedDueDay(31),
      );

      expect(rule.resolveFrom(2026, 1), DateTime.utc(2026, 2, 28));
      expect(rule.resolveFrom(2028, 1), DateTime.utc(2028, 2, 29));
    });

    test('should return a UTC date, never a local one', () {
      const DueRule rule = DueRule(
        monthsAfterPeriodEnd: 1,
        day: LastDayOfMonth(),
      );

      final DateTime resolved = rule.resolveFrom(2026, 5);

      expect(resolved.isUtc, isTrue);
      expect(resolved, DateTime.utc(2026, 6, 30));
    });
  });

  group('DueSchedule', () {
    test('should keep "no deadline" and "unconfirmed" apart', () {
      const DueSchedule none = NoDueDate('nothing is paid');
      const DueSchedule unverified = UnverifiedDueDate('payment day');

      expect(none, isA<NoDueDate>());
      expect(none, isNot(isA<UnverifiedDueDate>()));
      expect(unverified, isA<UnverifiedDueDate>());
      expect(unverified, isNot(isA<NoDueDate>()));
    });
  });
}
