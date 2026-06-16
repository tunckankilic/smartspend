import 'package:equatable/equatable.dart';

import 'package:smartspend/features/expenses/domain/entities/expense.dart';

/// Aggregated dashboard payload — owned by the bloc, rendered by widgets.
///
/// All money values are minor units (kuruş/cent). Dates in [dailyTotals]
/// are UTC midnight, one bucket per calendar day inside the selected
/// period (zero-padded for empty days so charts get a stable x-axis).
class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.currency,
    required this.currentTotalMinor,
    required this.previousTotalMinor,
    required this.byCategoryCurrent,
    required this.byCategoryPrevious,
    required this.dailyTotals,
    required this.recentExpenses,
    required this.topCategoryId,
    required this.expenseCount,
    this.byWeekdayMinor = const <int, int>{},
    this.tagFrequency = const <String, TagFrequencyAggregate>{},
  });

  static const DashboardSnapshot empty = DashboardSnapshot(
    currency: 'TRY',
    currentTotalMinor: 0,
    previousTotalMinor: 0,
    byCategoryCurrent: <int, int>{},
    byCategoryPrevious: <int, int>{},
    dailyTotals: <DateTime, int>{},
    recentExpenses: <Expense>[],
    topCategoryId: null,
    expenseCount: 0,
  );

  /// ISO-4217 code formatters render with. Sprint 4 freezes this at TRY;
  /// Sprint 6 will pick it up from `user_settings.default_currency`.
  final String currency;

  final int currentTotalMinor;
  final int previousTotalMinor;

  /// `categoryId → minor-unit total` for the current period. Categories
  /// with no expenses are absent rather than zero.
  final Map<int, int> byCategoryCurrent;

  /// Same shape as [byCategoryCurrent] for the previous period — used by
  /// the insight engine for per-category deltas.
  final Map<int, int> byCategoryPrevious;

  /// One bucket per calendar day in `[start, endExclusive)` (UTC). Days
  /// with no expenses are present with value `0` so the bar chart can
  /// render a continuous axis.
  final Map<DateTime, int> dailyTotals;

  /// Up to five newest expenses in the period, sorted by date desc.
  final List<Expense> recentExpenses;

  /// Largest-spend category id in the current period, or `null` if the
  /// period was empty.
  final int? topCategoryId;

  /// Number of expense rows that fell inside the current period.
  final int expenseCount;

  /// `ISO weekday → minor-unit total` for the current period.
  /// Keys: 1 = Monday … 7 = Sunday. Days with zero spending are absent.
  /// Used by [DayOfWeekInsight] evaluator.
  final Map<int, int> byWeekdayMinor;

  /// Per-tag aggregate for the current period (case-insensitive on
  /// match, original casing preserved on the key). Used by
  /// [FrequencyInsight] evaluator.
  final Map<String, TagFrequencyAggregate> tagFrequency;

  /// Signed percentage delta vs the previous period. `null` when the
  /// previous period was empty (delta is undefined). Positive = spent
  /// more this period than last.
  double? get deltaPercent {
    if (previousTotalMinor == 0) return null;
    final double prev = previousTotalMinor.toDouble();
    return ((currentTotalMinor - previousTotalMinor) / prev) * 100.0;
  }

  /// `true` when the current period had no expenses — UI swaps to an
  /// empty state.
  bool get isEmpty => expenseCount == 0;

  @override
  List<Object?> get props => <Object?>[
        currency,
        currentTotalMinor,
        previousTotalMinor,
        byCategoryCurrent,
        byCategoryPrevious,
        dailyTotals,
        recentExpenses,
        topCategoryId,
        expenseCount,
        byWeekdayMinor,
        tagFrequency,
      ];
}

/// Per-tag aggregate row: occurrence count + summed spend.
class TagFrequencyAggregate extends Equatable {
  const TagFrequencyAggregate({required this.count, required this.totalMinor});

  final int count;
  final int totalMinor;

  TagFrequencyAggregate add(int minor) {
    return TagFrequencyAggregate(
      count: count + 1,
      totalMinor: totalMinor + minor,
    );
  }

  @override
  List<Object?> get props => <Object?>[count, totalMinor];
}
