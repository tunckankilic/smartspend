import 'package:equatable/equatable.dart';

/// Sort order for the expense list. Sprint 3 ships four options that map
/// 1:1 to Drift `orderBy` clauses in the repository.
enum ExpenseSortOrder {
  /// Newest first (default).
  dateDesc,

  /// Oldest first.
  dateAsc,

  /// Largest first — useful for "where is my money going" scans.
  amountDesc,

  /// Smallest first.
  amountAsc,
}

/// Immutable filter snapshot consumed by `GetExpensesUseCase`.
///
/// The bloc rebuilds this whenever the user changes a chip / range
/// picker / search field, and hands it to the use case. Repositories
/// translate it into Drift query parameters.
class ExpenseFilter extends Equatable {
  const ExpenseFilter({
    this.dateFrom,
    this.dateTo,
    this.categoryIds = const <int>{},
    this.minAmount,
    this.maxAmount,
    this.searchQuery = '',
    this.sortOrder = ExpenseSortOrder.dateDesc,
  });

  /// Sentinel "no filter" — used by tests and the initial bloc state.
  static const ExpenseFilter empty = ExpenseFilter();

  /// Inclusive lower bound (UTC). `null` means "from the beginning of
  /// time".
  final DateTime? dateFrom;

  /// Inclusive upper bound (UTC). `null` means "until now".
  final DateTime? dateTo;

  /// Whitelist of category ids; empty set means "all categories".
  final Set<int> categoryIds;

  /// Inclusive lower bound on `amount` in minor units. `null` = no floor.
  final int? minAmount;

  /// Inclusive upper bound on `amount` in minor units. `null` = no cap.
  final int? maxAmount;

  /// Trimmed query string. The bloc applies this against
  /// `note` and the joined `receipts.store_name` (case-insensitive).
  final String searchQuery;

  final ExpenseSortOrder sortOrder;

  /// `true` when no filter is narrower than "everything". The list page
  /// uses this to render a placeholder when there are zero rows.
  bool get isUnfiltered {
    return dateFrom == null &&
        dateTo == null &&
        categoryIds.isEmpty &&
        minAmount == null &&
        maxAmount == null &&
        searchQuery.isEmpty;
  }

  ExpenseFilter copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<int>? categoryIds,
    int? minAmount,
    int? maxAmount,
    String? searchQuery,
    ExpenseSortOrder? sortOrder,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearMinAmount = false,
    bool clearMaxAmount = false,
  }) {
    return ExpenseFilter(
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      categoryIds: categoryIds ?? this.categoryIds,
      minAmount: clearMinAmount ? null : (minAmount ?? this.minAmount),
      maxAmount: clearMaxAmount ? null : (maxAmount ?? this.maxAmount),
      searchQuery: searchQuery ?? this.searchQuery,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        dateFrom,
        dateTo,
        categoryIds,
        minAmount,
        maxAmount,
        searchQuery,
        sortOrder,
      ];
}
