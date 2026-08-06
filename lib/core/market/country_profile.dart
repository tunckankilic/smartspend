import 'package:smartspend/core/market/document_type.dart';

/// Everything that varies by market (country) in one place.
///
/// A profile is pure data plus derived helpers — no I/O, no Flutter — so it
/// can be unit-tested and, later, mirrored by the `receipt_ocr` package's own
/// profile without sharing code across the package boundary.
///
/// Adding a market means adding one file (`de_profile.dart`) and registering
/// it in the [MarketRegistry]; no existing profile is edited.
///
/// VAT rates are **basis points** (`int`): 2000 = 20%, 100 = 1%. Never float.
abstract class CountryProfile {
  const CountryProfile();

  /// ISO 3166-1 alpha-2, uppercase (`TR`). Matches `companies.country_code`.
  String get countryCode;

  /// ISO 4217 currency of the market (`TRY`).
  String get currencyCode;

  /// Legal VAT rates in basis points, ascending, including 0.
  ///
  /// Drives the rate picker on the review screen and the buckets of the VAT
  /// report; the OCR layer snaps parsed rates onto this set.
  List<int> get vatRatesBp;

  /// Rate pre-selected for a line the parser could not classify.
  int get defaultVatRateBp;

  /// Document kinds that exist in this market, in the order a picker should
  /// present them.
  List<DocumentType> get documentTypes;

  /// Language code this market's users get when the device language is not
  /// one we ship. Ties into `AppLocalizations.supportedLocales`.
  String get defaultLanguageCode;

  /// Whether [rateBp] is a legal rate in this market.
  bool isVatRateSupported(int rateBp) => vatRatesBp.contains(rateBp);

  /// Whether [type] exists in this market.
  bool isDocumentTypeSupported(DocumentType type) =>
      documentTypes.contains(type);

  /// Snaps an arbitrary (OCR-derived, possibly noisy) rate onto the nearest
  /// legal rate. Ties go to the lower rate, which under-claims VAT rather
  /// than over-claiming it.
  int nearestVatRateBp(int rateBp) {
    int best = vatRatesBp.first;
    int bestDistance = (rateBp - best).abs();
    for (final int candidate in vatRatesBp.skip(1)) {
      final int distance = (rateBp - candidate).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// VAT on a net [baseMinor] at [rateBp], in the same minor unit.
  ///
  /// Integer arithmetic throughout, rounding half away from zero — the same
  /// rule Turkish receipts use.
  int vatOnBase(int baseMinor, int rateBp) =>
      _divRound(baseMinor * rateBp, 10000);

  /// VAT contained in a gross (VAT-inclusive) [grossMinor] at [rateBp].
  int vatFromGross(int grossMinor, int rateBp) =>
      _divRound(grossMinor * rateBp, 10000 + rateBp);

  static int _divRound(int numerator, int denominator) {
    if (denominator == 0) {
      return 0;
    }
    final int sign = (numerator < 0) == (denominator < 0) ? 1 : -1;
    final int n = numerator.abs();
    final int d = denominator.abs();
    return sign * ((2 * n + d) ~/ (2 * d));
  }
}
