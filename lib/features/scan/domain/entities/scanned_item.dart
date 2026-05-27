import 'package:equatable/equatable.dart';

/// A single line item parsed from a receipt.
///
/// Monetary values are stored as **cents / kuruş** (`int`) per the project
/// money rule — never `double`. [quantity] is a `num` so it can express both
/// whole units (`2`) and weighed goods (`0.345 kg`).
class ScannedItem extends Equatable {
  const ScannedItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.categoryId,
  });

  /// Empty placeholder used by Sprint 2.1 — Sprint 2.2 fills real values.
  factory ScannedItem.empty() => const ScannedItem(
    name: '',
    quantity: 1,
    unitPrice: 0,
    totalPrice: 0,
  );

  final String name;
  final num quantity;
  final int unitPrice;
  final int totalPrice;

  /// Resolved category id (local Drift PK). `null` until the user picks
  /// one in the edit screen or the AI categorizer (Sprint 4) fills it in.
  final int? categoryId;

  ScannedItem copyWith({
    String? name,
    num? quantity,
    int? unitPrice,
    int? totalPrice,
    int? categoryId,
    bool clearCategory = false,
  }) {
    return ScannedItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[name, quantity, unitPrice, totalPrice, categoryId];
}
