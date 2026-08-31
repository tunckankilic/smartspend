@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C6 — the Flutter toolchain is pinned in exactly one place and everything
/// else agrees with it.
///
/// Before this gate the repo carried two different answers: the dev machine
/// ran 3.44.8 while `codemagic.yaml` asked for 3.44.0. A green CI on 3.44.0
/// was verifying a toolchain nobody develops on. These tests fail the suite
/// the moment the two drift apart again.
///
/// **To bump Flutter:** change `.fvmrc`, change [_expectedDartSdk] to the Dart
/// version that release ships, run `flutter --version` to confirm, then update
/// `codemagic.yaml`. All three tests below have to stay green.
void main() {
  /// Dart SDK bundled with the Flutter release pinned in `.fvmrc`.
  /// Flutter 3.44.8 ships Dart 3.12.2 (measured with `flutter --version`).
  const String expectedDartSdk = '3.12.2';

  late final String pinnedFlutter = _readPinnedFlutterVersion();

  test('.fvmrc pins an exact Flutter version', () {
    expect(
      pinnedFlutter,
      matches(RegExp(r'^\d+\.\d+\.\d+$')),
      reason:
          'The pin must be an exact release, not a range or channel name. '
          'A channel would put CI and the dev machine back on different '
          'builds, which is what this gate exists to stop.',
    );
  });

  test('every codemagic.yaml workflow requests the pinned Flutter', () {
    final List<String> requested = _readCodemagicFlutterVersions();

    expect(
      requested,
      isNotEmpty,
      reason:
          'No `flutter:` key found in codemagic.yaml. If the CI config moved, '
          'point this test at the new file instead of deleting it.',
    );
    for (final String version in requested) {
      expect(
        version,
        pinnedFlutter,
        reason:
            'codemagic.yaml asks for Flutter $version but .fvmrc pins '
            '$pinnedFlutter. CI would verify a toolchain nobody develops on. '
            'Change both, or neither.',
      );
    }
  });

  test('the running Dart SDK matches the pinned Flutter release', () {
    // Platform.version looks like "3.12.2 (stable) (…) on \"macos_arm64\"".
    final String runningSdk = Platform.version.split(' ').first;

    expect(
      runningSdk,
      expectedDartSdk,
      reason:
          'This suite is running on Dart $runningSdk, but .fvmrc pins Flutter '
          '$pinnedFlutter which ships Dart $expectedDartSdk. Either switch to '
          'the pinned Flutter, or — if you deliberately upgraded — update '
          '.fvmrc, codemagic.yaml and `expectedDartSdk` in this file together.',
    );
  });
}

/// Reads the `flutter` key out of `.fvmrc` without pulling in a JSON/YAML
/// dependency for a two-line file.
String _readPinnedFlutterVersion() {
  final File file = File('.fvmrc');
  if (!file.existsSync()) {
    fail(
      '.fvmrc is missing. It is the single source of truth for the Flutter '
      'version; recreate it with {"flutter": "<x.y.z>"}.',
    );
  }
  final RegExpMatch? match = RegExp(
    r'"flutter"\s*:\s*"([^"]+)"',
  ).firstMatch(file.readAsStringSync());
  if (match == null) {
    fail('.fvmrc has no "flutter" key.');
  }
  return match.group(1)!;
}

/// Collects every `flutter: <version>` requested by a Codemagic workflow.
List<String> _readCodemagicFlutterVersions() {
  final File file = File('codemagic.yaml');
  if (!file.existsSync()) {
    fail('codemagic.yaml is missing.');
  }
  return RegExp(r'^\s*flutter:\s*(\S+)\s*$', multiLine: true)
      .allMatches(file.readAsStringSync())
      .map((RegExpMatch m) => m.group(1)!)
      .toList(growable: false);
}
