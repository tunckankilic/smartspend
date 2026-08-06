import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:smartspend/core/database/daos/user_settings_dao.dart';

/// Feature toggles for the pre-accounting (ön muhasebe) transformation.
///
/// Every business capability built during the 2.0.0 pivot ships behind one of
/// these flags. Defaults are compile-time constants and all of them are
/// **off**, so an in-flight sprint can land on `main` (and even reach the
/// store as part of a hotfix) without changing what users see. They are
/// flipped on together at launch (Faz 5.7); the mechanism stays afterwards as
/// a kill switch.
enum FeatureFlag {
  /// Business (`type='business'`) spaces: the space switcher, business space
  /// creation, and every query scoped to a non-personal company.
  businessSpaces('business_spaces'),

  /// Document archive: `documents` / `document_lines`, the review queue and
  /// manual document entry.
  documents('documents'),

  /// Contacts (cari): customer/supplier records, balances and statements.
  contacts('contacts'),

  /// Monthly VAT (KDV) report derived from approved document lines.
  vatReport('vat_report'),

  /// RevenueCat paywall and the Pro gating that redirects into it.
  paywall('paywall'),

  /// Staff invites and role-restricted UI.
  multiUser('multi_user');

  const FeatureFlag(this.key);

  /// Stable identifier used in storage and logs. Never rename — persisted
  /// overrides key off it.
  final String key;

  /// Key under which a debug override is stored in the `user_settings` table.
  String get settingsKey => 'feature_flag.$key';
}

/// Compile-time defaults. All flags ship disabled until the 2.0.0 launch
/// sprint flips them (Faz 5.7).
const Map<FeatureFlag, bool> kFeatureFlagDefaults = <FeatureFlag, bool>{
  FeatureFlag.businessSpaces: false,
  FeatureFlag.documents: false,
  FeatureFlag.contacts: false,
  FeatureFlag.vatReport: false,
  FeatureFlag.paywall: false,
  FeatureFlag.multiUser: false,
};

/// Reads feature flags synchronously.
///
/// Callers (widgets, routers, use cases) need an answer without awaiting, so
/// overrides are loaded once at boot via [load] and cached in memory.
/// Resolution order: debug override (debug builds only) → compile-time
/// default.
class FeatureFlagService {
  FeatureFlagService({
    required this.settingsDao,
    this.defaults = kFeatureFlagDefaults,
    this.allowOverrides = kDebugMode,
  });

  final UserSettingsDao settingsDao;

  /// Compile-time value of each flag. Injectable so tests can prove the
  /// override layer works in both directions.
  final Map<FeatureFlag, bool> defaults;

  /// Whether persisted overrides are honoured. `kDebugMode` in production
  /// wiring; tests pass `true` explicitly. Release builds always answer from
  /// [defaults], so a stale override row can never enable an unfinished
  /// feature for a real user.
  final bool allowOverrides;

  final Map<FeatureFlag, bool> _overrides = <FeatureFlag, bool>{};

  bool _loaded = false;

  /// Whether [load] has completed. Before that, [isEnabled] answers from the
  /// compile-time defaults only.
  bool get isLoaded => _loaded;

  /// Loads persisted overrides into memory. Call once during app boot, after
  /// the database is ready. In a build without override support this is a
  /// no-op beyond marking the service loaded.
  Future<void> load() async {
    _overrides.clear();
    if (allowOverrides) {
      for (final FeatureFlag flag in FeatureFlag.values) {
        final String? raw = await settingsDao.getValue(flag.settingsKey);
        final bool? parsed = _parse(raw);
        if (parsed != null) {
          _overrides[flag] = parsed;
        }
      }
    }
    _loaded = true;
  }

  /// Whether [flag] is on for this build/device.
  bool isEnabled(FeatureFlag flag) {
    if (allowOverrides) {
      final bool? override = _overrides[flag];
      if (override != null) {
        return override;
      }
    }
    return defaults[flag] ?? false;
  }

  /// The compile-time value of [flag], ignoring any override.
  bool defaultOf(FeatureFlag flag) => defaults[flag] ?? false;

  /// The active override for [flag], or `null` when none applies.
  bool? overrideOf(FeatureFlag flag) =>
      allowOverrides ? _overrides[flag] : null;

  /// Sets the debug override for [flag].
  ///
  /// Returns `false` without touching storage when the build does not support
  /// overrides — callers can surface "unavailable in release" instead of
  /// silently pretending the toggle took effect.
  Future<bool> setOverride(FeatureFlag flag, {required bool enabled}) async {
    if (!allowOverrides) {
      return false;
    }
    _overrides[flag] = enabled;
    await settingsDao.setValue(flag.settingsKey, enabled.toString());
    return true;
  }

  /// Drops the override for [flag], returning it to its compile-time default.
  Future<bool> clearOverride(FeatureFlag flag) async {
    if (!allowOverrides) {
      return false;
    }
    _overrides.remove(flag);
    await settingsDao.setValue(flag.settingsKey, _kUnsetValue);
    return true;
  }

  /// Clears every debug override, returning the service to compile-time
  /// defaults.
  Future<bool> clearOverrides() async {
    if (!allowOverrides) {
      return false;
    }
    _overrides.clear();
    for (final FeatureFlag flag in FeatureFlag.values) {
      await settingsDao.setValue(flag.settingsKey, _kUnsetValue);
    }
    return true;
  }

  /// Sentinel written when an override is cleared. The settings table has no
  /// delete accessor, and an unparseable value already means "no override".
  static const String _kUnsetValue = 'unset';

  static bool? _parse(String? raw) {
    switch (raw) {
      case 'true':
        return true;
      case 'false':
        return false;
      default:
        return null;
    }
  }
}
