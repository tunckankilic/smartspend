/// Supabase resource identifiers.
///
/// Storage bucket names, Edge Function names, and dart-define keys live here.
/// Migration filenames are tracked in `supabase/migrations/`.
abstract class SupabaseConstants {
  SupabaseConstants._();

  // dart-define keys (read via String.fromEnvironment).
  static const String envUrl = 'SUPABASE_URL';
  static const String envAnonKey = 'SUPABASE_ANON_KEY';

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
