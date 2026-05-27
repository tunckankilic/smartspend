import 'package:intl/intl.dart';

/// Locale + currency aware formatting helpers for monetary values.
///
/// Internally we store every amount as an `int` in **minor units** — kuruş
/// for TRY, cents for EUR/USD/GBP. The presentation layer turns those into
/// strings via this module so we never lose precision to `double` arithmetic.
///
/// Hoisted from `features/scan/presentation/widgets/scan_money` in Sprint 3
/// so every feature (Expenses, Dashboard, Budget, Scan) can share the same
/// formatter. The contract is identical to the Sprint 2.3 version, with an
/// extra [formatMinorCompact] helper for tight UI surfaces.

/// Pretty-print a minor-unit amount using a locale-aware currency format.
///
/// * `formatMinor(123456, 'TRY', locale: 'tr')` → `"1.234,56 ₺"`
/// * `formatMinor(123456, 'EUR', locale: 'de')` → `"1.234,56 €"`
/// * `formatMinor(123456, 'USD', locale: 'en_US')` → `"$1,234.56"`
String formatMinor(int minor, String currency, {String? locale}) {
  final NumberFormat fmt = NumberFormat.currency(
    locale: locale,
    name: currency,
    symbol: _symbolFor(currency),
    decimalDigits: 2,
  );
  return fmt.format(minor / 100.0);
}

/// Same as [formatMinor] but uses `NumberFormat.compactCurrency` — useful
/// for chart axes and dense list rows where `1.234,56 ₺` would overflow.
String formatMinorCompact(int minor, String currency, {String? locale}) {
  final NumberFormat fmt = NumberFormat.compactCurrency(
    locale: locale,
    name: currency,
    symbol: _symbolFor(currency),
    decimalDigits: 1,
  );
  return fmt.format(minor / 100.0);
}

String _symbolFor(String currency) {
  switch (currency) {
    case 'TRY':
      return '₺';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'USD':
      return r'$';
    default:
      return currency;
  }
}

/// Parse a user-typed price (`12,50` or `12.50`) back into minor units.
///
/// Returns `null` for empty / non-numeric / NaN / Infinity inputs so the
/// caller can render a validation error.
int? parseMinorInput(String input) {
  if (input.trim().isEmpty) return null;
  final String normalized = input.replaceAll(',', '.');
  final double? value = double.tryParse(normalized);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return (value * 100).round();
}

/// Currencies that SmartSpend supports out of the box. Settings pickers and
/// receipt edit dropdowns iterate over this list.
const List<String> kSupportedCurrencies = <String>['TRY', 'EUR', 'GBP', 'USD'];

/// Map a [currency] code → its glyph. Used by avatars / leading icons that
/// don't want to invoke a full `NumberFormat`.
String currencySymbol(String currency) => _symbolFor(currency);
