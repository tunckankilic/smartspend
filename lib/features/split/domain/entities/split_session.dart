import 'package:equatable/equatable.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';

/// In-memory, page-scoped state of a receipt-split workflow (Sprint 7).
///
/// `SplitSession` is intentionally **not** persisted. It lives only
/// inside `SplitBloc` during the user's visit to `SplitPage`. Closing
/// the page discards the session — matches the prompt's spec
/// ("session'lar lokalde saklanır, kalıcı arşiv değil") and keeps the
/// feature shippable without a Supabase migration.
///
/// Field conventions:
///   * `participants` — ordered, used as the display order for chips.
///   * `assignments` — sparse map. Missing key ⇒ item is unassigned and
///     the calculator treats it as shared across all participants.
///   * `splitType == equal` ⇒ calculator ignores assignments entirely.
class SplitSession extends Equatable {
  const SplitSession({
    required this.receiptId,
    required this.storeName,
    required this.receiptDate,
    required this.currency,
    required this.totalMinor,
    required this.items,
    required this.participants,
    required this.assignments,
    required this.splitType,
  });

  /// Bootstrap an empty session for a receipt — no participants yet.
  factory SplitSession.bootstrap({
    required int receiptId,
    required String? storeName,
    required DateTime receiptDate,
    required String currency,
    required int totalMinor,
    required List<SplitItem> items,
  }) {
    return SplitSession(
      receiptId: receiptId,
      storeName: storeName ?? '',
      receiptDate: receiptDate,
      currency: currency,
      totalMinor: totalMinor,
      items: items,
      participants: const <Participant>[],
      assignments: const <int, List<String>>{},
      splitType: SplitType.equal,
    );
  }

  final int receiptId;
  final String storeName;
  final DateTime receiptDate;
  final String currency;

  /// Total of the receipt in minor units. The calculator validates that
  /// per-person totals sum to this within a 1-cent rounding tolerance.
  final int totalMinor;
  final List<SplitItem> items;
  final List<Participant> participants;

  /// Per-item assignment map: `itemId → ordered list of participant ids`.
  /// Order is irrelevant for the calculator but is preserved for UI
  /// stability so chips don't reshuffle on every rebuild.
  final Map<int, List<String>> assignments;

  final SplitType splitType;

  SplitSession copyWith({
    String? storeName,
    DateTime? receiptDate,
    String? currency,
    int? totalMinor,
    List<SplitItem>? items,
    List<Participant>? participants,
    Map<int, List<String>>? assignments,
    SplitType? splitType,
  }) {
    return SplitSession(
      receiptId: receiptId,
      storeName: storeName ?? this.storeName,
      receiptDate: receiptDate ?? this.receiptDate,
      currency: currency ?? this.currency,
      totalMinor: totalMinor ?? this.totalMinor,
      items: items ?? this.items,
      participants: participants ?? this.participants,
      assignments: assignments ?? this.assignments,
      splitType: splitType ?? this.splitType,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        receiptId,
        storeName,
        receiptDate,
        currency,
        totalMinor,
        items,
        participants,
        assignments,
        splitType,
      ];
}
