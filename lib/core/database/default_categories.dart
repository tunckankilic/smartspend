/// Canonical default categories seeded on first launch.
///
/// The [remoteId] UUIDs are stable across clients and match the rows seeded
/// by `supabase/migrations/*_seed_default_categories.sql` (Sprint 8). Do not
/// regenerate them — sync depends on these IDs being identical everywhere.
///
/// Icon names map to Material symbol identifiers used by the UI layer.
class DefaultCategoryDefinition {
  const DefaultCategoryDefinition({
    required this.remoteId,
    required this.name,
    required this.icon,
    required this.color,
    required this.sortOrder,
  });

  final String remoteId;
  final String name;
  final String icon;
  final int color;
  final int sortOrder;
}

/// Ordered list — index also drives [DefaultCategoryDefinition.sortOrder].
const List<DefaultCategoryDefinition> kDefaultCategories =
    <DefaultCategoryDefinition>[
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000001',
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    sortOrder: 1,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000002',
    name: 'Restoran',
    icon: 'restaurant',
    color: 0xFFFF5722,
    sortOrder: 2,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000003',
    name: 'Kahve',
    icon: 'coffee',
    color: 0xFF795548,
    sortOrder: 3,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000004',
    name: 'Ulaşım',
    icon: 'directions_bus',
    color: 0xFF2196F3,
    sortOrder: 4,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000005',
    name: 'Yakıt',
    icon: 'local_gas_station',
    color: 0xFF607D8B,
    sortOrder: 5,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000006',
    name: 'Faturalar',
    icon: 'receipt_long',
    color: 0xFF9C27B0,
    sortOrder: 6,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000007',
    name: 'Kira',
    icon: 'home',
    color: 0xFF3F51B5,
    sortOrder: 7,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000008',
    name: 'Sağlık',
    icon: 'medical_services',
    color: 0xFFF44336,
    sortOrder: 8,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000009',
    name: 'Giyim',
    icon: 'checkroom',
    color: 0xFFE91E63,
    sortOrder: 9,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000010',
    name: 'Eğlence',
    icon: 'movie',
    color: 0xFFFF9800,
    sortOrder: 10,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000011',
    name: 'Elektronik',
    icon: 'devices',
    color: 0xFF00BCD4,
    sortOrder: 11,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000012',
    name: 'Spor',
    icon: 'fitness_center',
    color: 0xFF8BC34A,
    sortOrder: 12,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000013',
    name: 'Evcil Hayvan',
    icon: 'pets',
    color: 0xFFFFEB3B,
    sortOrder: 13,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000014',
    name: 'Hediye',
    icon: 'card_giftcard',
    color: 0xFFCE93D8,
    sortOrder: 14,
  ),
  DefaultCategoryDefinition(
    remoteId: '11111111-1111-1111-1111-000000000015',
    name: 'Diğer',
    icon: 'more_horiz',
    color: 0xFF9E9E9E,
    sortOrder: 15,
  ),
];
