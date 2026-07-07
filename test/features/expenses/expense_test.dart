import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';

/// Pins [Expense.copyWith] — especially the `clear*` flags, which are
/// the only way to null out receipt / note / recurring period (a plain
/// `null` argument means "leave unchanged").
void main() {
  const Category category = Category(
    id: 1,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    isCustom: false,
  );

  final Expense expense = Expense(
    id: 10,
    amount: 4000,
    category: category,
    receiptId: 3,
    note: 'haftalık',
    date: DateTime.utc(2026, 3, 26),
    currency: 'TRY',
    isManual: false,
    isRecurring: true,
    recurringPeriod: RecurringPeriod.weekly,
    isPendingSync: true,
    tags: const <String>['market'],
  );

  group('Expense.copyWith', () {
    test('should return an equal copy when nothing changes', () {
      expect(expense.copyWith(), expense);
    });

    test('should replace only the provided fields', () {
      final Expense updated = expense.copyWith(
        amount: 4500,
        note: 'aylık',
        isPendingSync: false,
        tags: const <String>['market', 'ev'],
      );
      expect(updated.amount, 4500);
      expect(updated.note, 'aylık');
      expect(updated.isPendingSync, isFalse);
      expect(updated.tags, const <String>['market', 'ev']);
      // Untouched fields survive.
      expect(updated.id, 10);
      expect(updated.receiptId, 3);
      expect(updated.recurringPeriod, RecurringPeriod.weekly);
    });

    test('should null out receipt / note / period via clear flags', () {
      final Expense cleared = expense.copyWith(
        clearReceipt: true,
        clearNote: true,
        clearRecurringPeriod: true,
      );
      expect(cleared.receiptId, isNull);
      expect(cleared.note, isNull);
      expect(cleared.recurringPeriod, isNull);
    });

    test('should keep receipt and note when clear flags stay false', () {
      final Expense kept = expense.copyWith(amount: 4100);
      expect(kept.receiptId, 3);
      expect(kept.note, 'haftalık');
    });
  });
}
