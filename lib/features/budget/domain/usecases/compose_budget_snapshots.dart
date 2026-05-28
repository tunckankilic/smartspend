import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';

/// Pure helper that turns `(budgets, expenses, categories, now)` into
/// the rich [BudgetSnapshot] list both [BudgetBloc] and [DashboardBloc]
/// render against.
///
/// Extracted from `BudgetBloc` in Sprint 6 so the dashboard insight
/// pipeline can reuse the same composition without dragging the BLoC
/// into a domain file.
class BudgetSnapshotComposer {
  const BudgetSnapshotComposer._();

  static List<BudgetSnapshot> compose({
    required List<Budget> budgets,
    required List<Expense> expenses,
    required List<Category> categories,
    required DateTime now,
  }) {
    final List<BudgetSnapshot> result = <BudgetSnapshot>[];
    for (final Budget b in budgets) {
      final BudgetWindow window = BudgetWindow.current(
        period: b.period,
        startDate: b.startDate,
        now: now,
      );
      final int spent = _sumExpensesIn(
        expenses: expenses,
        window: window,
        categoryId: b.categoryId,
      );
      result.add(
        BudgetSnapshot(
          budget: b,
          window: window,
          status: BudgetStatusCalculator.calculate(
            spentMinor: spent,
            amountMinor: b.amountMinor,
          ),
          category: _categoryFor(categories, b.categoryId),
        ),
      );
    }
    return result;
  }

  static int _sumExpensesIn({
    required List<Expense> expenses,
    required BudgetWindow window,
    required int? categoryId,
  }) {
    int total = 0;
    for (final Expense e in expenses) {
      if (!window.contains(e.date)) continue;
      if (categoryId != null && e.category.id != categoryId) continue;
      total += e.amount;
    }
    return total;
  }

  static Category? _categoryFor(List<Category> categories, int? id) {
    if (id == null) return null;
    for (final Category c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}
