import 'package:equatable/equatable.dart';

/// User-driven filter applied to the archive grid (Sprint 7).
///
/// Immutable — `copyWith` returns a new value rather than mutating in
/// place so it composes cleanly with Equatable in `ReceiptArchiveBloc`.
class ReceiptArchiveFilter extends Equatable {
  const ReceiptArchiveFilter({
    this.searchQuery,
    this.from,
    this.to,
  });

  /// Empty filter — the default at archive mount time.
  static const ReceiptArchiveFilter empty = ReceiptArchiveFilter();

  /// Case-insensitive substring search on `store_name`. Null / blank
  /// disables the predicate.
  final String? searchQuery;

  /// Inclusive lower bound on receipt date (UTC). Null means open.
  final DateTime? from;

  /// Inclusive upper bound on receipt date (UTC). Null means open.
  final DateTime? to;

  bool get isEmpty =>
      (searchQuery == null || searchQuery!.trim().isEmpty) &&
      from == null &&
      to == null;

  ReceiptArchiveFilter copyWith({
    String? searchQuery,
    DateTime? from,
    DateTime? to,
    bool clearSearchQuery = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return ReceiptArchiveFilter(
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
    );
  }

  @override
  List<Object?> get props => <Object?>[searchQuery, from, to];
}
