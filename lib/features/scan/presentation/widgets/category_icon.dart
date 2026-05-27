import 'package:flutter/material.dart';

/// Maps the icon names persisted in the `categories` table to concrete
/// [IconData]. Keeping this table inside the scan feature for now —
/// Sprint 3's Categories feature will hoist it into `core/`.
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

IconData iconForCategory(String name) {
  return kCategoryIcons[name] ?? Icons.label_rounded;
}
