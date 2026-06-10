/// Application-wide constants.
///
/// Pin every magic value here. Never hardcode bundle ids, callback URIs, or
/// limits in feature code.
abstract class AppConstants {
  AppConstants._();

  /// iOS / Android bundle identifier — owner controls the `.site` TLD.
  static const String bundleId = 'site.tunckankilic.smartspend';

  /// OAuth + magic-link deep link target. Must match `Info.plist`
  /// `CFBundleURLSchemes` and `AndroidManifest.xml` intent filter.
  static const String oauthCallbackUrl =
      'site.tunckankilic.smartspend://login-callback';

  // ───────────────────────────────────────────────────────────────────────
  // TODO(release): replace with the PUBLIC privacy-policy URL before submit.
  // Must be the same URL entered in App Store Connect → App Privacy. Source
  // text lives in docs/internal/appstore/privacy_policy_{en,tr,de}.md.
  // ───────────────────────────────────────────────────────────────────────
  static const String privacyPolicyUrl =
      'https://REPLACE_WITH_PRIVACY_POLICY_URL';

  // ───────────────────────────────────────────────────────────────────────
  // TODO(release): replace with the PUBLIC terms-of-use URL before submit.
  // If you decide NOT to host Terms, remove the Terms link from Settings and
  // the sign-up screen and drop "Terms of Use" from authTermsLabel instead.
  // ───────────────────────────────────────────────────────────────────────
  static const String termsOfUseUrl = 'https://REPLACE_WITH_TERMS_OF_USE_URL';

  /// Default currency used when the user has not set one yet.
  static const String defaultCurrency = 'TRY';

  /// Supported locales (must match `lib/l10n/app_*.arb`).
  static const List<String> supportedLocales = <String>['tr', 'en', 'de'];
  static const String fallbackLocale = 'tr';

  /// Gemini OCR fallback — client-side guard. The Edge Function enforces the
  /// real limit via a Postgres token bucket; this is just a UX-level cap.
  static const int maxGeminiFallbacksPerDay = 20;

  /// Cached image policy (cached_network_image).
  static const Duration imageCacheStaleAfter = Duration(days: 7);
  static const Duration imageCacheMaxAge = Duration(days: 30);
}
