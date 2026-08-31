import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:smartspend/core/database/daos/user_settings_dao.dart';

/// Feature toggles for the pre-accounting (ön muhasebe) transformation.
///
/// Every business capability built during the pivot ships behind one of these
/// flags. Defaults are compile-time constants and all of them are **off**, so
/// an in-flight sprint can land on `main` (and even reach the store as part of
/// a hotfix) without changing what users see. The mechanism stays afterwards
/// as a kill switch.
///
/// ## Every flag has a death date
///
/// A flag with no removal deadline stops being a release tool and becomes
/// permanent dead weight: six of these sat here for months with zero
/// references anywhere in `lib/`. So [FeatureFlag.shipsIn],
/// [FeatureFlag.removeBy] and [FeatureFlag.owner] are **required** — a flag
/// cannot be added without them — and
/// `test/core/services/feature_flag_lifecycle_test.dart` fails the build once
/// a flag outlives its [FeatureFlag.removeBy].
///
/// Read [FeatureFlag.removeBy] as a deadline, not a prediction: "by the time
/// this version is being built, the flag and its branches are gone."
enum FeatureFlag {
  /// Business (`type='business'`) spaces: the space switcher, business space
  /// creation, and every query scoped to a non-personal company.
  ///
  /// The data layer lands earlier, in 1.4.0, behind its own flag; this one
  /// only covers the UI that lets a user create and switch into one.
  businessSpaces(
    'business_spaces',
    shipsIn: '1.5.0',
    removeBy: '1.6.0',
    owner: _kOwner,
  ),

  /// Document archive: `documents` / `document_lines`, the review queue and
  /// manual document entry.
  documents(
    'documents',
    shipsIn: '1.5.0',
    removeBy: '1.6.0',
    owner: _kOwner,
  ),

  /// Contacts (cari): customer/supplier records, balances and statements.
  contacts(
    'contacts',
    shipsIn: '1.6.0',
    removeBy: '2.0.0',
    owner: _kOwner,
  ),

  /// Monthly VAT (KDV) report derived from approved document lines.
  vatReport(
    'vat_report',
    shipsIn: '1.6.0',
    removeBy: '2.0.0',
    owner: _kOwner,
  ),

  /// RevenueCat paywall and the Pro gating that redirects into it.
  paywall(
    'paywall',
    shipsIn: '1.5.0',
    removeBy: '1.6.0',
    owner: _kOwner,
  ),

  /// Staff invites and role-restricted UI.
  ///
  /// 2.0.0 is itself conditional on proven demand, and its successor has no
  /// name yet — 2.1.0 is the deadline, not a roadmap claim. If 2.0.0 slips or
  /// never happens, the gate will say so out loud instead of letting this sit
  /// here unexamined.
  multiUser(
    'multi_user',
    shipsIn: '2.0.0',
    removeBy: '2.1.0',
    owner: _kOwner,
  );

  const FeatureFlag(
    this.key, {
    required this.shipsIn,
    required this.removeBy,
    required this.owner,
  });

  /// Stable identifier used in storage and logs. Never rename — persisted
  /// overrides key off it.
  final String key;

  /// Release this flag is expected to be turned on in, as `X.Y.Z`.
  final String shipsIn;

  /// Release by which this flag and every branch behind it must be **gone**,
  /// as `X.Y.Z`. Once `pubspec.yaml` reaches this version the lifecycle test
  /// fails, which is the whole point: the deadline is enforced, not noted.
  final String removeBy;

  /// Who answers for this flag's removal. One name today; the field exists so
  /// the answer does not become "nobody" the moment there is a second person.
  final String owner;

  /// Key under which a debug override is stored in the `user_settings` table.
  String get settingsKey => 'feature_flag.$key';

  /// Whether this flag has outlived [removeBy] at [version].
  ///
  /// True when [removeBy] is at or below [version] — at that point the release
  /// it was supposed to disappear in has arrived.
  bool isOverdueAt(String version) => compareVersions(removeBy, version) <= 0;
}

/// Sole maintainer today. Kept as a constant so the field is one edit away
/// from being meaningful rather than six.
const String _kOwner = 'tunckankilic';

/// Orders two `X.Y.Z` version strings, returning a negative number when [a]
/// precedes [b], zero when they match, and a positive number otherwise.
///
/// Deliberately strict: anything that is not three dotted integers throws
/// rather than sorting to an arbitrary position, because a typo in a
/// [FeatureFlag.removeBy] would otherwise disable the deadline silently.
int compareVersions(String a, String b) {
  final List<int> left = _parseVersion(a);
  final List<int> right = _parseVersion(b);
  for (int i = 0; i < 3; i++) {
    final int diff = left[i] - right[i];
    if (diff != 0) {
      return diff;
    }
  }
  return 0;
}

List<int> _parseVersion(String version) {
  final RegExpMatch? match = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)$',
  ).firstMatch(version);
  if (match == null) {
    throw FormatException('Not an X.Y.Z version', version);
  }
  return <int>[
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

/// Compile-time defaults. Every flag ships disabled; each is flipped by the
/// release named in its [FeatureFlag.shipsIn].
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
