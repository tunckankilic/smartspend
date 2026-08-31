@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/services/feature_flag_service.dart';

/// C9 — the flag lifecycle gate.
///
/// A feature flag with no removal deadline is not a release tool, it is dead
/// weight: all six of these sat in the enum for months with zero references
/// anywhere in `lib/`. `shipsIn` / `removeBy` / `owner` are required
/// constructor arguments, so a flag cannot be *added* without a deadline; this
/// file is what stops one from quietly *outliving* it.
///
/// When these fail, the fix is to delete the flag and inline the branch it
/// guarded — not to push the date out. Moving `removeBy` is a decision worth
/// making on purpose, in a commit that says so.
void main() {
  group('compareVersions', () {
    test('should order versions component by component', () {
      expect(compareVersions('1.3.0', '1.4.0'), isNegative);
      expect(compareVersions('1.4.0', '1.3.0'), isPositive);
      expect(compareVersions('1.3.0', '1.3.0'), isZero);
      // Numeric, not lexicographic: '1.10.0' is after '1.9.0'.
      expect(compareVersions('1.10.0', '1.9.0'), isPositive);
      expect(compareVersions('2.0.0', '1.99.99'), isPositive);
      expect(compareVersions('1.3.1', '1.3.0'), isPositive);
    });

    test('should throw on anything that is not X.Y.Z', () {
      // A silently-tolerated typo in `removeBy` would switch the deadline off
      // without anyone noticing, so malformed input is an error, not a guess.
      for (final String bad in <String>['1.3', '1.3.0+2', 'v1.3.0', '', 'x']) {
        expect(
          () => compareVersions(bad, '1.0.0'),
          throwsFormatException,
          reason: '"$bad" should not parse as a version',
        );
      }
    });
  });

  group('FeatureFlag lifecycle', () {
    final String currentVersion = _readPubspecVersionName();

    test('should not carry a flag that has outlived its removeBy', () {
      final List<FeatureFlag> overdue = FeatureFlag.values
          .where((FeatureFlag f) => f.isOverdueAt(currentVersion))
          .toList();

      expect(
        overdue.map((FeatureFlag f) => '${f.key} (removeBy ${f.removeBy})'),
        isEmpty,
        reason:
            'pubspec.yaml is at $currentVersion and these flags were due to be '
            'gone by now. Delete the flag and inline the branch it guarded. '
            'If the feature genuinely slipped, move removeBy in its own commit '
            'and say why.',
      );
    });

    test('should ship before it is removed', () {
      for (final FeatureFlag flag in FeatureFlag.values) {
        expect(
          compareVersions(flag.shipsIn, flag.removeBy),
          isNegative,
          reason:
              '${flag.key} ships in ${flag.shipsIn} but is due gone by '
              '${flag.removeBy} — that leaves it no release to live in.',
        );
      }
    });

    test('should name an owner for every flag', () {
      for (final FeatureFlag flag in FeatureFlag.values) {
        expect(
          flag.owner.trim(),
          isNotEmpty,
          reason: '${flag.key} has no owner',
        );
      }
    });

    test('should give every flag a compile-time default', () {
      // A missing entry answers `false` via the `?? false` fallback, which
      // looks identical to a deliberate "off" — and would hide a flag that was
      // meant to be on.
      for (final FeatureFlag flag in FeatureFlag.values) {
        expect(
          kFeatureFlagDefaults.containsKey(flag),
          isTrue,
          reason: '${flag.key} is missing from kFeatureFlagDefaults',
        );
      }
    });

    test('should be referenced in lib/ once its release has shipped', () {
      // The other half of the disease this gate treats: all six flags existed
      // for months with zero `FeatureFlag.` references anywhere in lib/, so
      // they gated nothing at all.
      //
      // The check only applies to flags whose shipsIn is *strictly before* the
      // version being built — a flag ships in the release currently under
      // development, so demanding a reference during that sprint would just
      // paint the suite red while the feature is being written.
      final Set<String> referenced = _flagsReferencedInLib();

      for (final FeatureFlag flag in FeatureFlag.values) {
        if (compareVersions(flag.shipsIn, currentVersion) >= 0) {
          continue;
        }
        expect(
          referenced,
          contains(flag.name),
          reason:
              '${flag.key} was due to ship in ${flag.shipsIn} and pubspec is '
              'already at $currentVersion, but nothing in lib/ reads it. '
              'Either it is gating something and the wiring is missing, or it '
              'is decoration and should be deleted.',
        );
      }
    });

    test('should report every flag overdue once its removeBy arrives', () {
      // Proves the gate can actually bite. Without this, the "no overdue
      // flags" test above passes just as happily if `isOverdueAt` were
      // hardcoded to false.
      for (final FeatureFlag flag in FeatureFlag.values) {
        expect(
          flag.isOverdueAt(flag.removeBy),
          isTrue,
          reason: '${flag.key} is not flagged overdue at its own removeBy',
        );
        expect(
          flag.isOverdueAt('99.0.0'),
          isTrue,
          reason: '${flag.key} is not flagged overdue at a far future release',
        );
        expect(
          flag.isOverdueAt(flag.shipsIn),
          isFalse,
          reason: '${flag.key} is flagged overdue in the release it ships in',
        );
      }
    });
  });
}

/// Reads the `X.Y.Z` half of pubspec's `version:` line — the version currently
/// being built, which is what a `removeBy` deadline is measured against.
String _readPubspecVersionName() {
  final RegExpMatch? match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync());
  if (match == null) {
    fail('Could not read an X.Y.Z version out of pubspec.yaml.');
  }
  return match.group(1)!;
}

/// Enum names that appear as `FeatureFlag.<name>` somewhere under `lib/`.
///
/// The enum's own file is skipped: it necessarily mentions every value, so
/// counting it would make the check pass for free. Generated sources are
/// skipped for the same reason they are excluded from coverage.
Set<String> _flagsReferencedInLib() {
  const String definitionPath = 'lib/core/services/feature_flag_service.dart';
  final Set<String> found = <String>{};

  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final String path = entity.path;
    if (path == definitionPath ||
        path.endsWith('.g.dart') ||
        path.contains('/generated/')) {
      continue;
    }
    for (final RegExpMatch match
        in RegExp(r'FeatureFlag\.(\w+)').allMatches(entity.readAsStringSync())) {
      found.add(match.group(1)!);
    }
  }
  return found;
}
