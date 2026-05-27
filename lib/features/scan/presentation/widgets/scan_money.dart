import 'package:intl/intl.dart';

/// Pretty-prints a minor-unit amount (kuruş/cent) using a locale-aware
/// currency format. Kept inside the scan feature for Sprint 2.3 — Sprint 5
/// hoists a richer `CurrencyFormatter` into `core/utils`.
String formatMinor(int minor, String currency, {String? locale}) {
  final NumberFormat fmt = NumberFormat.currency(
    locale: locale,
    name: currency,
    symbol: _symbolFor(currency),
    decimalDigits: 2,
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

/// Parses a user-typed price (`12,50` or `12.50`) back into minor units.
int? parseMinorInput(String input) {
  if (input.trim().isEmpty) return null;
  final String normalized = input.replaceAll(',', '.');
  final double? value = double.tryParse(normalized);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return (value * 100).round();
}
