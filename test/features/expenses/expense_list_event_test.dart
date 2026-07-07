import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_list_bloc.dart';

/// Equality contracts for [ExpenseListEvent] subtypes — the bloc relies
/// on Equatable to dedupe re-dispatched filter events.
void main() {
  group('ExpenseListEvent equality', () {
    test('should treat value-less events as equal', () {
      expect(const ExpensesSubscribed(), const ExpensesSubscribed());
      expect(const FiltersCleared(), const FiltersCleared());
      expect(const ExpensesRefreshed(), const ExpensesRefreshed());
    });

    test('should compare FilterChanged by filter snapshot', () {
      expect(
        const FilterChanged(filter: ExpenseFilter.empty),
        const FilterChanged(filter: ExpenseFilter.empty),
      );
    });

    test('should compare CategoryFilterToggled by category id', () {
      expect(
        const CategoryFilterToggled(categoryId: 2),
        const CategoryFilterToggled(categoryId: 2),
      );
      expect(
        const CategoryFilterToggled(categoryId: 2),
        isNot(const CategoryFilterToggled(categoryId: 3)),
      );
    });

    test('should compare DateRangeChanged by both bounds', () {
      final DateTime from = DateTime.utc(2026, 1, 1);
      final DateTime to = DateTime.utc(2026, 1, 31);
      expect(
        DateRangeChanged(from: from, to: to),
        DateRangeChanged(from: from, to: to),
      );
      expect(
        DateRangeChanged(from: from, to: to),
        isNot(DateRangeChanged(from: from)),
      );
    });

    test('should compare AmountRangeChanged by min/max', () {
      expect(
        const AmountRangeChanged(min: 100, max: 500),
        const AmountRangeChanged(min: 100, max: 500),
      );
      expect(
        const AmountRangeChanged(min: 100),
        isNot(const AmountRangeChanged(max: 100)),
      );
    });

    test('should compare SortChanged by order', () {
      expect(
        const SortChanged(order: ExpenseSortOrder.dateDesc),
        const SortChanged(order: ExpenseSortOrder.dateDesc),
      );
      expect(
        const SortChanged(order: ExpenseSortOrder.dateDesc),
        isNot(const SortChanged(order: ExpenseSortOrder.amountDesc)),
      );
    });

    test('should compare SearchQueried by query', () {
      expect(
        const SearchQueried(query: 'kahve'),
        const SearchQueried(query: 'kahve'),
      );
      expect(
        const SearchQueried(query: 'kahve'),
        isNot(const SearchQueried(query: 'çay')),
      );
    });

    test('should compare ExpenseDeleted by id', () {
      expect(const ExpenseDeleted(id: 5), const ExpenseDeleted(id: 5));
      expect(const ExpenseDeleted(id: 5), isNot(const ExpenseDeleted(id: 6)));
    });
  });
}
