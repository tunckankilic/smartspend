import 'package:equatable/equatable.dart';

/// Lightweight, domain-friendly view of a category row.
///
/// Sprint 3 builds a fully-fledged Categories feature with its own
/// repository; until then the scan feature owns this minimal shape so the
/// edit UI can render the picker without leaking Drift types into
/// presentation.
class ScanCategory extends Equatable {
  const ScanCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.isCustom,
  });

  /// Local Drift PK. Stable for the lifetime of the install.
  final int id;
  final String name;

  /// Material symbol identifier (e.g. `shopping_cart`). Mapped to
  /// [IconData] by the presentation layer.
  final String icon;

  /// Packed ARGB integer (`0xFFRRGGBB`).
  final int color;
  final bool isCustom;

  @override
  List<Object?> get props => <Object?>[id, name, icon, color, isCustom];
}
