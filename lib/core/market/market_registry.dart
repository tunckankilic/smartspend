import 'package:smartspend/core/market/country_profile.dart';
import 'package:smartspend/core/market/tr_profile.dart';

/// Thrown when a country code has no [CountryProfile] in this build.
class UnsupportedMarketException implements Exception {
  const UnsupportedMarketException(this.countryCode);

  final String countryCode;

  @override
  String toString() =>
      'UnsupportedMarketException: no CountryProfile for "$countryCode"';
}

/// Holds the profiles this build ships and which one is active.
///
/// The active market follows the active company's `country_code` (Faz 3).
/// Until spaces exist, the registry simply stays on [TrProfile] — resolution
/// is already routed through here so switching later touches one call site.
class MarketRegistry {
  MarketRegistry({
    List<CountryProfile> profiles = const <CountryProfile>[TrProfile()],
    String activeCountryCode = 'TR',
  }) : assert(
          profiles.isNotEmpty,
          'MarketRegistry needs at least one profile',
        ) {
    for (final CountryProfile profile in profiles) {
      _profiles[_normalise(profile.countryCode)] = profile;
    }
    setActive(activeCountryCode);
  }

  final Map<String, CountryProfile> _profiles = <String, CountryProfile>{};

  late CountryProfile _active;

  /// The profile every market-dependent lookup should go through.
  CountryProfile get active => _active;

  /// Country codes this build can serve, uppercase.
  List<String> get supportedCountryCodes =>
      _profiles.keys.toList(growable: false);

  /// Whether [countryCode] has a profile in this build.
  bool supports(String countryCode) =>
      _profiles.containsKey(_normalise(countryCode));

  /// The profile for [countryCode], or `null` when unsupported.
  CountryProfile? profileFor(String countryCode) =>
      _profiles[_normalise(countryCode)];

  /// Switches the active market.
  ///
  /// Throws [UnsupportedMarketException] rather than silently falling back:
  /// a company row pointing at a market this build cannot serve is a bug we
  /// want to see, not a quietly wrong VAT table.
  void setActive(String countryCode) {
    final CountryProfile? profile = profileFor(countryCode);
    if (profile == null) {
      throw UnsupportedMarketException(countryCode);
    }
    _active = profile;
  }

  /// Switches to [countryCode] when supported, otherwise keeps the current
  /// profile. Returns whether the switch happened.
  bool setActiveIfSupported(String countryCode) {
    final CountryProfile? profile = profileFor(countryCode);
    if (profile == null) {
      return false;
    }
    _active = profile;
    return true;
  }

  static String _normalise(String countryCode) => countryCode.toUpperCase();
}
