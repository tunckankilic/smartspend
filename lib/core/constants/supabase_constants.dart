/// Supabase resource identifiers.
///
/// Storage bucket names, Edge Function names, and dart-define keys live here.
/// Migration filenames are tracked in `supabase/migrations/`.
abstract class SupabaseConstants {
  SupabaseConstants._();

  // dart-define keys (read via String.fromEnvironment).
  static const String envUrl = 'SUPABASE_URL';
  static const String envAnonKey = 'SUPABASE_ANON_KEY';

  /// Google OAuth client IDs for the native `signInWithIdToken` flow. The web
  /// client is the audience Supabase validates the ID token against; the iOS
  /// client is required by the Google Sign-In SDK on iOS. Both injected via
  /// `--dart-define-from-file=.env`; empty in dev until configured.
  static const String envGoogleWebClientId = 'GOOGLE_WEB_CLIENT_ID';
  static const String envGoogleIosClientId = 'GOOGLE_IOS_CLIENT_ID';

  // Storage buckets.
  static const String receiptsBucket = 'receipts';

  // Edge Function names — match `supabase/functions/<name>/index.ts`.
  static const String fnGeminiOcrFallback = 'gemini-ocr-fallback';
  static const String fnWeeklySummary = 'weekly-summary';
  static const String fnExportCsv = 'export-csv';

  /// Signed URL TTL for receipt images.
  static const Duration signedUrlTtl = Duration(hours: 1);

  /// PKCE redirect — matches [AppConstants.oauthCallbackUrl] but kept separate
  /// so backend code can depend on it without pulling in app constants.
  static const String oauthRedirectUrl =
      'site.tunckankilic.smartspend://login-callback';
}
