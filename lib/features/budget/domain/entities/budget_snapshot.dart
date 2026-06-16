import 'package:equatable/equatable.dart';

import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';

/// One budget + everything the BudgetPage needs to render it.
///
/// Assembled by the BLoC (Big Step 3) by combining:
///   * [Budget] from `BudgetRepository.watchActiveBudgets`,
///   * the current [BudgetWindow] (computed from `now`),
///   * the matching aggregate spent from `ExpenseRepository.watchExpenses`,
///   * a denormalized category snapshot (icon/color/name).
///
/// Keeping these together as a value object lets widget tests pass a
/// canned `BudgetSnapshot` without spinning up the bloc pipeline.
class BudgetSnapshot extends Equatable {
  const BudgetSnapshot({
    required this.budget,
    required this.window,
    required this.status,
    this.category,
  });

  final Budget budget;
  final BudgetWindow window;
  final BudgetStatus status;

  /// Denormalized category — `null` for general budgets.
  final Category? category;

  bool get isGeneral => budget.isGeneral;

  @override
  List<Object?> get props => <Object?>[budget, window, status, category];
}
