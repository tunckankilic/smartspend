import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';

void main() {
  group('BudgetWindow.current', () {
    test('weekly should anchor on startDate, 7-day half-open', () {
      final BudgetWindow w = BudgetWindow.current(
        period: BudgetPeriod.weekly,
        startDate: DateTime.utc(2026, 5, 4), // Monday
        now: DateTime.utc(2026, 5, 12), // Following Tuesday
      );
      expect(w.startUtc, DateTime.utc(2026, 5, 11));
      expect(w.endUtcExclusive, DateTime.utc(2026, 5, 18));
      expect(w.length, const Duration(days: 7));
    });

    test('monthly should anchor on day-of-month', () {
      final BudgetWindow w = BudgetWindow.current(
        period: BudgetPeriod.monthly,
        startDate: DateTime.utc(2026, 3, 15),
        now: DateTime.utc(2026, 5, 20),
      );
      expect(w.startUtc, DateTime.utc(2026, 5, 15));
      expect(w.endUtcExclusive, DateTime.utc(2026, 6, 15));
    });

    test('monthly should clamp day 31 in shorter months', () {
      final BudgetWindow w = BudgetWindow.current(
        period: BudgetPeriod.monthly,
        startDate: DateTime.utc(2026, 1, 31),
        now: DateTime.utc(2026, 2, 10),
      );
      expect(w.startUtc, DateTime.utc(2026, 1, 31));
      // Feb has 28 days in 2026 — anchor clamps.
      expect(w.endUtcExclusive, DateTime.utc(2026, 2, 28));
    });

    test('yearly should anchor on month+day', () {
      final BudgetWindow w = BudgetWindow.current(
        period: BudgetPeriod.yearly,
        startDate: DateTime.utc(2024, 3, 1),
        now: DateTime.utc(2026, 7, 15),
      );
      expect(w.startUtc, DateTime.utc(2026, 3, 1));
      expect(w.endUtcExclusive, DateTime.utc(2027, 3, 1));
    });

    test('yearly should clamp Feb 29 in non-leap years', () {
      final BudgetWindow w = BudgetWindow.current(
        period: BudgetPeriod.yearly,
        startDate: DateTime.utc(2024, 2, 29),
        now: DateTime.utc(2025, 6, 1),
      );
      // 2025 is non-leap → window starts Feb 28.
      expect(w.startUtc, DateTime.utc(2025, 2, 28));
    });

    test('returns first window when now precedes startDate', () {
      final BudgetWindow w = BudgetWindow.current(
        period: BudgetPeriod.weekly,
        startDate: DateTime.utc(2026, 6, 1),
        now: DateTime.utc(2026, 5, 1),
      );
      expect(w.startUtc, DateTime.utc(2026, 6, 1));
      expect(w.endUtcExclusive, DateTime.utc(2026, 6, 8));
    });

    test('contains should be half-open [start, end)', () {
      final BudgetWindow w = BudgetWindow(
        startUtc: DateTime.utc(2026, 5, 1),
        endUtcExclusive: DateTime.utc(2026, 5, 8),
      );
      expect(w.contains(DateTime.utc(2026, 5, 1)), isTrue);
      expect(w.contains(DateTime.utc(2026, 5, 7, 23)), isTrue);
      expect(w.contains(DateTime.utc(2026, 5, 8)), isFalse);
      expect(w.contains(DateTime.utc(2026, 4, 30)), isFalse);
    });
  });
}
