import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/daos/user_settings_dao.dart';
import 'package:smartspend/core/services/feature_flag_service.dart';

import '../../helpers/test_database.dart';

void main() {
  group('FeatureFlagService', () {
    late AppDatabase db;
    late UserSettingsDao dao;

    setUp(() {
      db = createTestDatabase();
      dao = db.userSettingsDao;
    });

    tearDown(() async {
      await db.close();
    });

    FeatureFlagService build({bool allowOverrides = true}) {
      return FeatureFlagService(
        settingsDao: dao,
        allowOverrides: allowOverrides,
      );
    }

    test('should ship every flag disabled by default', () {
      final FeatureFlagService service = build();

      for (final FeatureFlag flag in FeatureFlag.values) {
        expect(
          service.isEnabled(flag),
          isFalse,
          reason: '${flag.key} must default to off until the 2.0.0 launch',
        );
      }
    });

    test('should expose a stable settings key per flag', () {
      expect(
        FeatureFlag.businessSpaces.settingsKey,
        'feature_flag.business_spaces',
      );
      expect(FeatureFlag.vatReport.settingsKey, 'feature_flag.vat_report');
      expect(
        FeatureFlag.values.map((FeatureFlag f) => f.key).toSet(),
        hasLength(FeatureFlag.values.length),
      );
    });

    test('should report not loaded before load() is awaited', () async {
      final FeatureFlagService service = build();
      expect(service.isLoaded, isFalse);

      await service.load();

      expect(service.isLoaded, isTrue);
    });

    test('should answer from defaults before load() when an override exists',
        () async {
      await dao.setValue(FeatureFlag.documents.settingsKey, 'true');
      final FeatureFlagService service = build();

      expect(service.isEnabled(FeatureFlag.documents), isFalse);
    });

    test('should apply a persisted override after load()', () async {
      await dao.setValue(FeatureFlag.documents.settingsKey, 'true');
      final FeatureFlagService service = build();

      await service.load();

      expect(service.isEnabled(FeatureFlag.documents), isTrue);
      expect(service.overrideOf(FeatureFlag.documents), isTrue);
      expect(service.defaultOf(FeatureFlag.documents), isFalse);
      // Sibling flags are untouched.
      expect(service.isEnabled(FeatureFlag.contacts), isFalse);
    });

    test('should ignore an unparseable stored value', () async {
      await dao.setValue(FeatureFlag.paywall.settingsKey, 'yes-please');
      final FeatureFlagService service = build();

      await service.load();

      expect(service.isEnabled(FeatureFlag.paywall), isFalse);
      expect(service.overrideOf(FeatureFlag.paywall), isNull);
    });

    test('should persist an override set at runtime', () async {
      final FeatureFlagService service = build();
      await service.load();

      final bool applied =
          await service.setOverride(FeatureFlag.multiUser, enabled: true);

      expect(applied, isTrue);
      expect(service.isEnabled(FeatureFlag.multiUser), isTrue);

      final FeatureFlagService reloaded = build();
      await reloaded.load();
      expect(reloaded.isEnabled(FeatureFlag.multiUser), isTrue);
    });

    test('should clear a single override back to its default', () async {
      final FeatureFlagService service = build();
      await service.load();
      await service.setOverride(FeatureFlag.contacts, enabled: true);

      final bool cleared = await service.clearOverride(FeatureFlag.contacts);

      expect(cleared, isTrue);

      expect(service.isEnabled(FeatureFlag.contacts), isFalse);
      expect(service.overrideOf(FeatureFlag.contacts), isNull);

      final FeatureFlagService reloaded = build();
      await reloaded.load();
      expect(reloaded.isEnabled(FeatureFlag.contacts), isFalse);
    });

    test('should clear every override at once', () async {
      final FeatureFlagService service = build();
      await service.load();
      await service.setOverride(FeatureFlag.documents, enabled: true);
      await service.setOverride(FeatureFlag.contacts, enabled: true);

      final bool cleared = await service.clearOverrides();

      expect(cleared, isTrue);
      for (final FeatureFlag flag in FeatureFlag.values) {
        expect(service.isEnabled(flag), isFalse);
      }
    });

    test('should honour a false override against an enabled default',
        () async {
      final FeatureFlagService service = FeatureFlagService(
        settingsDao: dao,
        defaults: const <FeatureFlag, bool>{FeatureFlag.paywall: true},
        allowOverrides: true,
      );
      await service.load();
      expect(service.isEnabled(FeatureFlag.paywall), isTrue);

      await service.setOverride(FeatureFlag.paywall, enabled: false);

      expect(service.isEnabled(FeatureFlag.paywall), isFalse);
    });

    test('should fall back to off for a flag missing from the defaults map',
        () {
      final FeatureFlagService service = FeatureFlagService(
        settingsDao: dao,
        defaults: const <FeatureFlag, bool>{},
        allowOverrides: true,
      );

      expect(service.isEnabled(FeatureFlag.businessSpaces), isFalse);
      expect(service.defaultOf(FeatureFlag.businessSpaces), isFalse);
    });

    group('without override support (release build)', () {
      test('should ignore a stored override', () async {
        await dao.setValue(FeatureFlag.documents.settingsKey, 'true');
        final FeatureFlagService service = build(allowOverrides: false);

        await service.load();

        expect(service.allowOverrides, isFalse);
        expect(service.isEnabled(FeatureFlag.documents), isFalse);
        expect(service.overrideOf(FeatureFlag.documents), isNull);
      });

      test('should refuse to write an override', () async {
        final FeatureFlagService service = build(allowOverrides: false);
        await service.load();

        final bool applied =
            await service.setOverride(FeatureFlag.documents, enabled: true);

        expect(applied, isFalse);
        expect(service.isEnabled(FeatureFlag.documents), isFalse);
        expect(
          await dao.getValue(FeatureFlag.documents.settingsKey),
          isNull,
        );
      });

      test('should refuse to clear overrides', () async {
        final FeatureFlagService service = build(allowOverrides: false);

        expect(await service.clearOverrides(), isFalse);
        expect(await service.clearOverride(FeatureFlag.documents), isFalse);
      });
    });
  });
}
