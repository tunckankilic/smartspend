import 'package:flutter_test/flutter_test.dart';
import 'package:smartspend/core/utils/category_display_name.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/l10n/generated/app_localizations_en.dart';
import 'package:smartspend/l10n/generated/app_localizations_tr.dart';

Category _category({
  required String icon,
  required String name,
  bool isCustom = false,
}) {
  return Category(
    id: 1,
    name: name,
    icon: icon,
    color: 0xFF000000,
    isCustom: isCustom,
  );
}

void main() {
  final AppLocalizationsEn en = AppLocalizationsEn();
  final AppLocalizationsTr tr = AppLocalizationsTr();

  group('localizedCategoryName', () {
    test('should localize a default category by its icon in English', () {
      // Stored name is the canonical Turkish seed; the UI must follow locale.
      expect(
        localizedCategoryName(en, _category(icon: 'home', name: 'Kira')),
        'Rent',
      );
      expect(
        localizedCategoryName(
          en,
          _category(icon: 'shopping_cart', name: 'Market'),
        ),
        'Groceries',
      );
    });

    test('should keep the Turkish name for a default category in Turkish', () {
      expect(
        localizedCategoryName(tr, _category(icon: 'home', name: 'Kira')),
        'Kira',
      );
    });

    test('should fall back to the stored name for custom categories', () {
      // A user category may reuse a default icon — isCustom must win.
      expect(
        localizedCategoryName(
          en,
          _category(icon: 'home', name: 'Yazlık kira', isCustom: true),
        ),
        'Yazlık kira',
      );
    });

    test('should fall back to the stored name for an unknown icon', () {
      expect(
        localizedCategoryName(
          en,
          _category(icon: 'rocket_launch', name: 'Roket'),
        ),
        'Roket',
      );
    });
  });
}
