import 'package:equatable/equatable.dart';

/// A receipt as shown in the archive grid / list (Sprint 7).
///
/// Trimmed projection over the Drift `Receipt` row: just the fields the
/// archive page renders. Sprint 8 will replace `imagePath` (local file)
/// with a Supabase Storage signed URL — the entity shape stays the same.
class ReceiptArchiveEntry extends Equatable {
  const ReceiptArchiveEntry({
    required this.id,
    required this.date,
    required this.totalMinor,
    required this.currency,
    this.storeName,
    this.imagePath,
    this.warrantyEndDate,
  });

  /// Local Drift PK. Used as GoRouter path param on the detail page.
  final int id;

  /// Display name as parsed by the OCR pipeline. Empty receipts fall
  /// back to "Unknown store" at the UI layer — never embed that string
  /// here so it can be localized.
  final String? storeName;

  /// Receipt date in UTC. Display layer formats with the device locale.
  final DateTime date;

  final int totalMinor;
  final String currency;

  /// Absolute local file path. Null when the receipt was created
  /// without an image (manual entry) or the local cache was evicted.
  final String? imagePath;

  /// Optional warranty expiry (Sprint 7). Null means "no warranty
  /// tracking" — the UI surfaces a "Add warranty" CTA instead of an
  /// expiry chip.
  final DateTime? warrantyEndDate;

  @override
  List<Object?> get props => <Object?>[
        id,
        storeName,
        date,
        totalMinor,
        currency,
        imagePath,
        warrantyEndDate,
      ];
}
