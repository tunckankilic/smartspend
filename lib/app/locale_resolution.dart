import 'package:flutter/widgets.dart' show Locale;

/// Picks the app language for [deviceLocale] out of [supported].
///
/// Extracted from `MaterialApp.localeResolutionCallback` so that code running
/// outside the widget tree — the boot-time schedulers, which compose
/// notification text before any `BuildContext` exists — resolves the language
/// exactly the way the UI does. Two copies of this rule would eventually
/// disagree, and the symptom would be a user reading the app in English and
/// receiving notifications in Turkish.
///
/// Falls back to English rather than to the template language: the template
/// ARB is Turkish, so an unhandled device locale would otherwise land a
/// French or Japanese user in Turkish.
Locale resolveAppLocale(Locale? deviceLocale, Iterable<Locale> supported) {
  if (deviceLocale != null) {
    for (final Locale candidate in supported) {
      if (candidate.languageCode == deviceLocale.languageCode) {
        return candidate;
      }
    }
  }
  return const Locale('en');
}
