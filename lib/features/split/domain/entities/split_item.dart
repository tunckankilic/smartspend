import 'package:equatable/equatable.dart';

/// A receipt line item as seen by the split engine (Sprint 7).
///
/// Decoupled from `ReceiptItem` (Drift row) so the calculator stays
/// pure — no Drift, no Supabase, no Flutter imports. The bloc maps a
/// `List<ReceiptItem>` into a `List<SplitItem>` once on session start.
///
/// `totalPriceMinor` is the line total in minor units (kuruş / cent),
/// already accounting for `quantity * unitPrice` upstream.
class SplitItem extends Equatable {
  const SplitItem({
    required this.id,
    required this.name,
    required this.totalPriceMinor,
  });

  /// Stable id tied to the source `ReceiptItem.id`.
  final int id;

  /// Display name as printed on the receipt.
  final String name;

  /// Line total in minor units. Always non-negative — refunded lines
  /// (rare on consumer receipts) are filtered upstream.
  final int totalPriceMinor;

  @override
  List<Object?> get props => <Object?>[id, name, totalPriceMinor];
}
