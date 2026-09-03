import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/app/locale_resolution.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// The rule that decides which language the user reads the app in — and,
/// since the boot-time schedulers share it, which language their notifications
/// arrive in. Two copies of this rule would disagree eventually, and the
/// symptom would be an English UI sending Turkish reminders.
void main() {
  const List<Locale> supported = AppLocalizations.supportedLocales;

  test('should follow the device language when we ship it', () {
    expect(
      resolveAppLocale(const Locale('tr', 'TR'), supported).languageCode,
      'tr',
    );
    expect(resolveAppLocale(const Locale('de'), supported).languageCode, 'de');
  });

  test('should fall back to English, not to the template language', () {
    // The template ARB is Turkish. Without the explicit fallback a French or
    // Japanese device would land in Turkish, which is worse than English for
    // everyone who is not Turkish.
    expect(resolveAppLocale(const Locale('fr'), supported).languageCode, 'en');
    expect(resolveAppLocale(const Locale('ja'), supported).languageCode, 'en');
  });

  test('should fall back to English when the device says nothing', () {
    expect(resolveAppLocale(null, supported).languageCode, 'en');
  });
}
