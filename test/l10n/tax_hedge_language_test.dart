import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨 The one copy rule this feature cannot bend.
///
/// Every deadline SmartSpend shows comes from a rule nobody has verified
/// against GİB. On a lock screen there is no room to qualify anything, so the
/// qualification has to be inside the sentence — and it has to survive the
/// next person who tidies the wording up. "Son gün bugün" is a claim the app
/// cannot support; "takvimimize göre son gün bugün, muhasebecinle teyit et"
/// is the same information without the false authority.
///
/// This reads the ARB files directly rather than the generated class, because
/// the ARB is what a translator edits and the generated code would only
/// confirm that codegen ran.
void main() {
  /// The clause that must appear, per language. Two halves each: whose
  /// calendar this is, and who to check it with.
  const Map<String, List<String>> hedges = <String, List<String>>{
    'tr': <String>['Takvimimize göre', 'teyit et'],
    'en': <String>['By our calendar', 'accountant'],
    'de': <String>['Nach unserem Kalender', 'Steuerberatung'],
  };

  /// Every notification body. These are the strings read without any
  /// surrounding screen to soften them.
  const List<String> reminderBodyKeys = <String>[
    'taxReminderBodyWeek',
    'taxReminderBodyTomorrow',
    'taxReminderBodyToday',
  ];

  Map<String, dynamic> arb(String language) => json.decode(
        File('lib/l10n/app_$language.arb').readAsStringSync(),
      ) as Map<String, dynamic>;

  for (final MapEntry<String, List<String>> entry in hedges.entries) {
    final String language = entry.key;
    final List<String> required = entry.value;

    test('$language reminder bodies never state a deadline as fact', () {
      final Map<String, dynamic> strings = arb(language);

      for (final String key in reminderBodyKeys) {
        final Object? value = strings[key];
        expect(
          value,
          isA<String>(),
          reason: '$key is missing from app_$language.arb',
        );
        for (final String clause in required) {
          expect(
            value! as String,
            contains(clause),
            reason: '$key in $language dropped "$clause" — a reminder that '
                'states an unverified deadline as fact',
          );
        }
      }
    });
  }

  test('the override caption keeps its hedge in every language', () {
    // A corrected date is still one we published, not one the user's
    // accountant confirmed to them.
    for (final MapEntry<String, List<String>> entry in hedges.entries) {
      final String caption =
          arb(entry.key)['taxDetailOverrideReason'] as String;
      expect(
        caption,
        contains(entry.value.last),
        reason: 'taxDetailOverrideReason in ${entry.key} lost its hedge',
      );
    }
  });

  test('every language carries the same reminder keys', () {
    // A missing key falls back to the template language, so a translator who
    // drops one turns a German user's notification Turkish rather than
    // producing a visible error.
    final Set<String> tr = arb('tr').keys.where(_visible).toSet();
    for (final String language in <String>['en', 'de']) {
      expect(
        arb(language).keys.where(_visible).toSet(),
        tr,
        reason: 'app_$language.arb has drifted from the template',
      );
    }
  });
}

bool _visible(String key) => !key.startsWith('@');
