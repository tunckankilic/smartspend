import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_group.dart';

Expense _expense(int id, DateTime date) {
  const Category cat = Category(
    id: 1,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    isCustom: false,
  );
  return Expense(
    id: id,
    amount: 1000,
    category: cat,
    date: date,
    currency: 'TRY',
    isManual: true,
    isRecurring: false,
    isPendingSync: false,
  );
}

void main() {
  final DateTime now = DateTime.utc(2026, 5, 27, 10);

  group('ExpenseGroupKey.resolve', () {
    test('should classify same-day rows as today', () {
      final ExpenseGroupKey k = ExpenseGroupKey.resolve(
        DateTime.utc(2026, 5, 27, 2),
        now: now,
      );
      expect(k, ExpenseGroupKey.today);
    });

    test('should classify yesterday correctly', () {
      final ExpenseGroupKey k = ExpenseGroupKey.resolve(
        DateTime.utc(2026, 5, 26, 23),
        now: now,
      );
      expect(k, ExpenseGroupKey.yesterday);
    });

    test('should classify dates 2–6 days back as thisWeek', () {
      final ExpenseGroupKey k = ExpenseGroupKey.resolve(
        DateTime.utc(2026, 5, 23),
        now: now,
      );
      expect(k, ExpenseGroupKey.thisWeek);
    });

    test('should classify earlier-in-month as thisMonth', () {
      final ExpenseGroupKey k = ExpenseGroupKey.resolve(
        DateTime.utc(2026, 5, 5),
        now: now,
      );
      expect(k, ExpenseGroupKey.thisMonth);
    });

    test('should classify previous-month rows as earlier', () {
      final ExpenseGroupKey k = ExpenseGroupKey.resolve(
        DateTime.utc(2026, 4, 1),
        now: now,
      );
      expect(k, ExpenseGroupKey.earlier);
    });
  });

  group('groupByDate', () {
    test('should preserve input order within each bucket', () {
      final List<Expense> input = <Expense>[
        _expense(1, DateTime.utc(2026, 5, 27, 9)),
        _expense(2, DateTime.utc(2026, 5, 27, 6)),
        _expense(3, DateTime.utc(2026, 5, 26, 22)),
      ];
      final List<ExpenseGroup> groups = groupByDate(input, now: now);
      expect(groups.length, 2);
      expect(groups[0].key, ExpenseGroupKey.today);
      expect(
        groups[0].expenses.map((Expense e) => e.id).toList(),
        <int>[1, 2],
      );
      expect(groups[1].key, ExpenseGroupKey.yesterday);
      expect(groups[1].expenses.map((Expense e) => e.id).toList(), <int>[3]);
    });

    test('should return an empty list for no input', () {
      expect(groupByDate(const <Expense>[], now: now), isEmpty);
    });

    test('should keep groups in chronological-priority order', () {
      final List<Expense> input = <Expense>[
        _expense(1, DateTime.utc(2026, 4, 1)), // earlier
        _expense(2, DateTime.utc(2026, 5, 5)), // thisMonth
        _expense(3, DateTime.utc(2026, 5, 27, 8)), // today
      ];
      final List<ExpenseGroup> groups = groupByDate(input, now: now);
      expect(
        groups.map((ExpenseGroup g) => g.key).toList(),
        <ExpenseGroupKey>[
          ExpenseGroupKey.today,
          ExpenseGroupKey.thisMonth,
          ExpenseGroupKey.earlier,
        ],
      );
    });
  });
}
