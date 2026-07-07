import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/presentation/bloc/add_expense_bloc.dart';

/// Equality contracts for [AddExpenseEvent] subtypes.
void main() {
  const Category category = Category(
    id: 1,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    isCustom: false,
  );

  group('AddExpenseEvent equality', () {
    test('should treat value-less events as equal', () {
      expect(const AddExpenseStarted(), const AddExpenseStarted());
      expect(const AddExpenseSubmitted(), const AddExpenseSubmitted());
    });

    test('should compare AmountChanged by raw input', () {
      expect(
        const AddExpenseAmountChanged(input: '12,50'),
        const AddExpenseAmountChanged(input: '12,50'),
      );
      expect(
        const AddExpenseAmountChanged(input: '12,50'),
        isNot(const AddExpenseAmountChanged(input: '13,00')),
      );
    });

    test('should compare CategorySelected by category', () {
      expect(
        const AddExpenseCategorySelected(category: category),
        const AddExpenseCategorySelected(category: category),
      );
    });

    test('should compare CategoryCreated by name, icon and color', () {
      expect(
        const AddExpenseCategoryCreated(
          name: 'Kitap',
          icon: 'book',
          color: 0xFF2196F3,
        ),
        const AddExpenseCategoryCreated(
          name: 'Kitap',
          icon: 'book',
          color: 0xFF2196F3,
        ),
      );
      expect(
        const AddExpenseCategoryCreated(
          name: 'Kitap',
          icon: 'book',
          color: 0xFF2196F3,
        ),
        isNot(
          const AddExpenseCategoryCreated(
            name: 'Kitap',
            icon: 'book',
            color: 0xFF4CAF50,
          ),
        ),
      );
    });

    test('should compare DateSelected by date', () {
      final DateTime date = DateTime.utc(2026, 7, 7);
      expect(
        AddExpenseDateSelected(date: date),
        AddExpenseDateSelected(date: date),
      );
      expect(
        AddExpenseDateSelected(date: date),
        isNot(AddExpenseDateSelected(date: DateTime.utc(2026, 7, 8))),
      );
    });

    test('should compare note and tag events by value', () {
      expect(
        const AddExpenseNoteChanged(note: 'öğle'),
        const AddExpenseNoteChanged(note: 'öğle'),
      );
      expect(
        const AddExpenseTagAdded(tag: 'kahve'),
        const AddExpenseTagAdded(tag: 'kahve'),
      );
      expect(
        const AddExpenseTagRemoved(tag: 'kahve'),
        isNot(const AddExpenseTagRemoved(tag: 'çay')),
      );
    });

    test('should compare recurring toggles and period changes by value', () {
      expect(
        const AddExpenseRecurringToggled(value: true),
        const AddExpenseRecurringToggled(value: true),
      );
      expect(
        const AddExpenseRecurringToggled(value: true),
        isNot(const AddExpenseRecurringToggled(value: false)),
      );
      expect(
        const AddExpensePeriodChanged(period: RecurringPeriod.monthly),
        const AddExpensePeriodChanged(period: RecurringPeriod.monthly),
      );
      expect(
        const AddExpensePeriodChanged(period: RecurringPeriod.monthly),
        isNot(const AddExpensePeriodChanged(period: RecurringPeriod.weekly)),
      );
    });
  });
}
