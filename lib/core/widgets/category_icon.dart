import 'package:flutter/material.dart';

/// Maps the icon names persisted in the `categories` table to concrete
/// [IconData].
///
/// Hoisted from `features/scan/presentation/widgets/category_icon` in
/// Sprint 3 so Expenses, Budget, Dashboard, and Scan can share the same
/// glyph table.
///
/// Keys match the `icon` column on `Categories`; see
/// `lib/core/database/default_categories.dart` for the seed list.
const Map<String, IconData> kCategoryIcons = <String, IconData>{
  'shopping_cart': Icons.shopping_cart_rounded,
  'restaurant': Icons.restaurant_rounded,
  'coffee': Icons.coffee_rounded,
  'directions_bus': Icons.directions_bus_rounded,
  'local_gas_station': Icons.local_gas_station_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'home': Icons.home_rounded,
  'medical_services': Icons.medical_services_rounded,
  'checkroom': Icons.checkroom_rounded,
  'movie': Icons.movie_rounded,
  'devices': Icons.devices_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'pets': Icons.pets_rounded,
  'card_giftcard': Icons.card_giftcard_rounded,
  'more_horiz': Icons.more_horiz_rounded,
};

/// Resolve a [IconData] for the persisted icon name. Unknown names fall
/// back to a neutral label glyph so custom categories never render as
/// blanks.
IconData iconForCategory(String name) {
  return kCategoryIcons[name] ?? Icons.label_rounded;
}
