import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/country_profile.dart';
import 'package:smartspend/core/market/document_type.dart';
import 'package:smartspend/core/market/market_registry.dart';
import 'package:smartspend/core/market/tr_profile.dart';

/// Stand-in for a future market file (DeProfile/UkProfile). Its only job here
/// is to prove the registry needs no edits when a market is added.
class _FakeProfile extends CountryProfile {
  const _FakeProfile();

  @override
  String get countryCode => 'DE';

  @override
  String get currencyCode => 'EUR';

  @override
  String get timeZone => 'Europe/Berlin';

  @override
  List<int> get vatRatesBp => const <int>[0, 700, 1900];

  @override
  int get defaultVatRateBp => 1900;

  @override
  List<DocumentType> get documentTypes =>
      const <DocumentType>[DocumentType.other];

  @override
  String get defaultLanguageCode => 'de';
}

void main() {
  group('MarketRegistry', () {
    test('should default to the Turkish profile', () {
      final MarketRegistry registry = MarketRegistry();

      expect(registry.active, isA<TrProfile>());
      expect(registry.active.countryCode, 'TR');
      expect(registry.supportedCountryCodes, <String>['TR']);
    });

    test('should serve an added market without touching existing profiles',
        () {
      final MarketRegistry registry = MarketRegistry(
        profiles: const <CountryProfile>[TrProfile(), _FakeProfile()],
      );

      expect(registry.supportedCountryCodes, containsAll(<String>['TR', 'DE']));
      expect(registry.supports('DE'), isTrue);
      expect(registry.profileFor('DE')?.currencyCode, 'EUR');
      expect(registry.active.countryCode, 'TR');
    });

    test('should switch the active market', () {
      final MarketRegistry registry = MarketRegistry(
        profiles: const <CountryProfile>[TrProfile(), _FakeProfile()],
      )..setActive('DE');

      expect(registry.active.countryCode, 'DE');
      expect(registry.active.vatRatesBp, <int>[0, 700, 1900]);
    });

    test('should treat country codes case-insensitively', () {
      final MarketRegistry registry = MarketRegistry(
        profiles: const <CountryProfile>[TrProfile(), _FakeProfile()],
        activeCountryCode: 'tr',
      );

      expect(registry.active.countryCode, 'TR');
      expect(registry.supports('de'), isTrue);
      registry.setActive('de');
      expect(registry.active.countryCode, 'DE');
    });

    test('should throw for an unsupported market rather than fall back', () {
      final MarketRegistry registry = MarketRegistry();

      expect(
        () => registry.setActive('FR'),
        throwsA(isA<UnsupportedMarketException>()),
      );
      expect(registry.active.countryCode, 'TR');
      expect(registry.profileFor('FR'), isNull);
      expect(registry.supports('FR'), isFalse);
    });

    test('should throw when constructed with an unsupported active market',
        () {
      expect(
        () => MarketRegistry(activeCountryCode: 'FR'),
        throwsA(isA<UnsupportedMarketException>()),
      );
    });

    test('should describe the unsupported market in the exception text', () {
      expect(
        const UnsupportedMarketException('FR').toString(),
        contains('FR'),
      );
    });

    test('should keep the current profile on a soft switch that misses', () {
      final MarketRegistry registry = MarketRegistry(
        profiles: const <CountryProfile>[TrProfile(), _FakeProfile()],
      );

      expect(registry.setActiveIfSupported('FR'), isFalse);
      expect(registry.active.countryCode, 'TR');

      expect(registry.setActiveIfSupported('DE'), isTrue);
      expect(registry.active.countryCode, 'DE');
    });
  });
}
