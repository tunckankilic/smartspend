import 'package:equatable/equatable.dart';

/// Aggregated totals returned by `GetExpenseSummaryUseCase`.
///
/// Sprint 3 surfaces the running total on the list app bar; Sprint 5's
/// dashboard reuses [byCategory] to render the pie / bar chart breakdown.
class ExpenseSummary extends Equatable {
  const ExpenseSummary({
    required this.totalMinor,
    required this.currency,
    required this.byCategory,
    required this.count,
  });

  /// Sum of all matched expenses, in minor units.
  final int totalMinor;

  /// Currency used to format [totalMinor]. Sprint 3 picks this from the
  /// most common currency among the matched rows; Sprint 5 will let the
  /// user override via settings.
  final String currency;

  /// `categoryId → minor-unit total` map. Categories with no expenses
  /// in the window are absent rather than zero.
  final Map<int, int> byCategory;

  /// Number of matched expense rows.
  final int count;

  static const ExpenseSummary empty = ExpenseSummary(
    totalMinor: 0,
    currency: 'TRY',
    byCategory: <int, int>{},
    count: 0,
  );

  @override
  List<Object?> get props =>
      <Object?>[totalMinor, currency, byCategory, count];
}
