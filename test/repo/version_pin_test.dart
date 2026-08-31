@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C7 — `pubspec.yaml` is the only place a version number is written down.
///
/// Before this gate the iOS project carried its own `MARKETING_VERSION = 1.0.1`
/// while pubspec said `1.2.1+2`. It happened to be harmless — `Info.plist`
/// reads `$(FLUTTER_BUILD_NAME)`, not `$(MARKETING_VERSION)` — but it was a
/// second, wrong answer sitting one Xcode setting away from being the shipped
/// one. These tests keep every platform deriving from pubspec so a release can
/// never be labelled with a version the source tree does not carry.
///
/// The matching half of the discipline lives in `codemagic.yaml`: a `v*` tag
/// whose version disagrees with pubspec fails the release build.
///
/// Deliberately NOT gated here: `CHANGELOG.md`. It is currently stale (it
/// documents 1.0.0 while 1.2.x ships), so a gate on it would either fail on
/// day one or be written loose enough to prove nothing.
void main() {
  late final _Version pubspecVersion = _readPubspecVersion();

  test('pubspec.yaml carries a well-formed `X.Y.Z+N` version', () {
    expect(
      pubspecVersion.name,
      matches(RegExp(r'^\d+\.\d+\.\d+$')),
      reason: 'Build name must be plain semver — App Store Connect rejects '
          'anything else, and the tag gate compares against it verbatim.',
    );
    expect(
      pubspecVersion.build,
      matches(RegExp(r'^\d+$')),
      reason: 'Build number must be a bare integer.',
    );
  });

  test('iOS Info.plist derives both version keys from Flutter', () {
    final String plist = _read('ios/Runner/Info.plist');

    expect(
      plist,
      contains(r'<string>$(FLUTTER_BUILD_NAME)</string>'),
      reason: 'CFBundleShortVersionString must come from pubspec.',
    );
    expect(
      plist,
      contains(r'<string>$(FLUTTER_BUILD_NUMBER)</string>'),
      reason: 'CFBundleVersion must come from pubspec.',
    );
  });

  test('the iOS Runner target hardcodes no version of its own', () {
    final String pbxproj = _read('ios/Runner.xcodeproj/project.pbxproj');

    // The Runner target's three build configurations. RunnerTests is
    // deliberately excluded: its configs inherit the Pods xcconfigs, not
    // Generated.xcconfig, so `$(FLUTTER_BUILD_NAME)` would resolve to empty
    // there. A test bundle's version never ships, so it is left alone.
    const Map<String, String> runnerConfigs = <String, String>{
      '97C147061CF9000F007C117D': 'Debug',
      '97C147071CF9000F007C117D': 'Release',
      '249021D4217E4FDB00AE95B9': 'Profile',
    };

    for (final MapEntry<String, String> entry in runnerConfigs.entries) {
      final String block = _buildConfigBlock(pbxproj, entry.key, entry.value);

      expect(
        block,
        contains(r'MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)"'),
        reason: 'Runner/${entry.value} pins its own MARKETING_VERSION instead '
            'of deriving it from pubspec. Verified resolution: '
            '`xcodebuild -showBuildSettings` reports the pubspec value.',
      );
      expect(
        block,
        contains(r'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"'),
        reason: 'Runner/${entry.value} pins its own CURRENT_PROJECT_VERSION '
            'instead of deriving it from pubspec.',
      );
    }
  });

  test('Android derives both version fields from Flutter', () {
    final String gradle = _read('android/app/build.gradle.kts');

    expect(gradle, contains('versionCode = flutter.versionCode'));
    expect(gradle, contains('versionName = flutter.versionName'));
  });
}

/// A `version: name+build` line, split into its two halves.
class _Version {
  const _Version(this.name, this.build);

  final String name;
  final String build;
}

_Version _readPubspecVersion() {
  final RegExpMatch? match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(_read('pubspec.yaml'));
  if (match == null) {
    fail('pubspec.yaml has no `version:` line.');
  }
  final List<String> parts = match.group(1)!.split('+');
  if (parts.length != 2) {
    fail(
      'pubspec version "${match.group(1)}" is not in `name+build` form. '
      'Both halves are required: the store rejects a build without one.',
    );
  }
  return _Version(parts[0], parts[1]);
}

/// Extracts a single `XCBuildConfiguration` block by its object id, so an
/// assertion cannot accidentally be satisfied by a different target's settings.
String _buildConfigBlock(String pbxproj, String objectId, String name) {
  final RegExpMatch? match = RegExp(
    '${RegExp.escape(objectId)} /\\* $name \\*/ = \\{.*?\n\t\t\\};\n',
    dotAll: true,
  ).firstMatch(pbxproj);
  if (match == null) {
    fail(
      'Build configuration $objectId ($name) is gone from project.pbxproj. '
      'If the Xcode project was regenerated, update the ids in this test — '
      'do not delete the check.',
    );
  }
  return match.group(0)!;
}

String _read(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing.');
  }
  return file.readAsStringSync();
}
