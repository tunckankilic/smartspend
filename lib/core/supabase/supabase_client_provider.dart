// coverage:ignore-file
// Supabase.initialize bootstrap; touches the live SDK at startup, not
// unit-testable.
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/constants/supabase_constants.dart';

/// Thin wrapper around [Supabase.initialize] / [Supabase.instance].
///
/// Owns the single [SupabaseClient] for the app. Register the [client] getter
/// inside `get_it`; never instantiate [SupabaseClient] elsewhere.
///
/// Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `--dart-define`. The
/// service role key MUST NOT ship with the app — it lives only in Edge
/// Function secrets and the Supabase dashboard.
class SupabaseClientProvider {
  SupabaseClientProvider._();

  static const String _supabaseUrl =
      String.fromEnvironment(SupabaseConstants.envUrl);
  static const String _supabaseAnonKey =
      String.fromEnvironment(SupabaseConstants.envAnonKey);

  /// Initialise the global Supabase singleton. Call exactly once from `main`
  /// before `runApp`.
  ///
  /// Throws [StateError] if the required dart-define env vars are missing —
  /// fail loud at startup rather than silently shipping a broken build.
  static Future<void> initialize() async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_ANON_KEY missing. '
        'Run with --dart-define-from-file=.env',
      );
    }

    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.warn,
      ),
    );
  }

  /// Process-wide [SupabaseClient]. Safe to call after [initialize].
  static SupabaseClient get client => Supabase.instance.client;
}
