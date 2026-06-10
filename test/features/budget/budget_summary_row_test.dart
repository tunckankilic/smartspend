import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_summary_row.dart';

void main() {
  group('BudgetSummaryRow.daysLeft', () {
    final BudgetWindow window = BudgetWindow(
      startUtc: DateTime.utc(2026, 6),
      endUtcExclusive: DateTime.utc(2026, 7),
    );

    test('should count full remaining days mid-window', () {
      // 7 full days between 24 June midnight and 1 July midnight.
      expect(
        BudgetSummaryRow.daysLeft(window, DateTime.utc(2026, 6, 24)),
        7,
      );
    });

    test('should round a partial day up', () {
      // 18:00 on 30 June → window ends in 6 hours → still "1 day".
      expect(
        BudgetSummaryRow.daysLeft(window, DateTime.utc(2026, 6, 30, 18)),
        1,
      );
    });

    test('should return 0 once the window has ended', () {
      expect(
        BudgetSummaryRow.daysLeft(window, DateTime.utc(2026, 7, 2)),
        0,
      );
    });

    test('should treat the exclusive end instant as 0', () {
      expect(
        BudgetSummaryRow.daysLeft(window, DateTime.utc(2026, 7)),
        0,
      );
    });

    test('should convert a local-time now to UTC before comparing', () {
      // Same instant as 30 June 21:00 UTC expressed with a +03:00 offset.
      final DateTime local = DateTime.utc(2026, 6, 30, 21).toLocal();
      expect(BudgetSummaryRow.daysLeft(window, local), 1);
    });
  });
}
