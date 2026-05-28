import 'package:equatable/equatable.dart';

/// A line item shown on the detail page (Sprint 7).
class ReceiptDetailItem extends Equatable {
  const ReceiptDetailItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.totalPriceMinor,
  });

  final int id;
  final String name;
  final double quantity;
  final int unitPriceMinor;
  final int totalPriceMinor;

  @override
  List<Object?> get props =>
      <Object?>[id, name, quantity, unitPriceMinor, totalPriceMinor];
}

/// Receipt + its items, for the detail page (Sprint 7).
///
/// Sprint 8 will lazy-load the image via a signed Supabase Storage URL.
/// Today the detail page falls back to the local `imagePath` cache.
class ReceiptDetail extends Equatable {
  const ReceiptDetail({
    required this.id,
    required this.date,
    required this.totalMinor,
    required this.currency,
    required this.items,
    this.storeName,
    this.imagePath,
    this.warrantyEndDate,
  });

  final int id;
  final String? storeName;
  final DateTime date;
  final int totalMinor;
  final String currency;
  final String? imagePath;
  final DateTime? warrantyEndDate;
  final List<ReceiptDetailItem> items;

  @override
  List<Object?> get props => <Object?>[
        id,
        storeName,
        date,
        totalMinor,
        currency,
        imagePath,
        warrantyEndDate,
        items,
      ];
}
