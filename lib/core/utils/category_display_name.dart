import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Localized display name for a [Category].
///
/// The 15 default categories are seeded with their canonical Turkish
/// [Category.name] (see `default_categories.dart`). The stored name is data,
/// not UI text, so it does not follow the app language on its own. Defaults
/// are keyed by their unique [Category.icon] — stable identifiers that never
/// change — and mapped to the active locale here. User-created categories
/// ([Category.isCustom] == true) keep the name the user typed.
String localizedCategoryName(AppLocalizations l, Category category) {
  if (category.isCustom) {
    return category.name;
  }
  switch (category.icon) {
    case 'shopping_cart':
      return l.categoryMarket;
    case 'restaurant':
      return l.categoryRestaurant;
    case 'coffee':
      return l.categoryCoffee;
    case 'directions_bus':
      return l.categoryTransport;
    case 'local_gas_station':
      return l.categoryFuel;
    case 'receipt_long':
      return l.categoryBills;
    case 'home':
      return l.categoryRent;
    case 'medical_services':
      return l.categoryHealth;
    case 'checkroom':
      return l.categoryClothing;
    case 'movie':
      return l.categoryEntertainment;
    case 'devices':
      return l.categoryElectronics;
    case 'fitness_center':
      return l.categorySports;
    case 'pets':
      return l.categoryPets;
    case 'card_giftcard':
      return l.categoryGifts;
    case 'more_horiz':
      return l.categoryOther;
    default:
      return category.name;
  }
}
