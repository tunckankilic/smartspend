import 'package:equatable/equatable.dart';

/// Domain-friendly view of a category row.
///
/// Sprint 3 promoted this from `features/scan/domain/entities/scan_category`
/// to its own feature so Expenses, Budget, Dashboard, and Scan can all share
/// the same shape without one depending on another.
///
/// The shape is intentionally minimal — no Drift, no Supabase, no Flutter
/// imports — so it can flow freely across all layers.
class Category extends Equatable {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.isCustom,
  });

  /// Local Drift PK. Stable for the lifetime of the install.
  final int id;

  /// Display name. Default categories are seeded in the user's locale.
  final String name;

  /// Material symbol identifier (e.g. `shopping_cart`). Mapped to
  /// [IconData] by the presentation layer via `core/widgets/category_icon`.
  final String icon;

  /// Packed ARGB integer (`0xFFRRGGBB`).
  final int color;

  /// `true` when the row was created by the user, `false` for the 15
  /// seeded defaults.
  final bool isCustom;

  @override
  List<Object?> get props => <Object?>[id, name, icon, color, isCustom];
}
