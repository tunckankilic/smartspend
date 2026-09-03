// coverage:ignore-file
// PostgREST wrapper for the tax override pull; the abstract seam is mocked in
// TaxRepositoryImpl tests, the concrete impl is a thin SDK passthrough.
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin, mockable seam over the `tax_calendar_overrides` table.
///
/// 🚨 Deliberately separate from `SyncRemoteDataSource`, and for a different
/// reason than [TelemetryRemoteDataSource] is. That datasource exists to push
/// the user's rows and pull them back scoped to `user_id`. These rows have no
/// `user_id`: they are published regulatory fact, identical for every
/// taxpayer, and the client must never author one. A method on the shared
/// datasource would put them one call away from the push path — and a client
/// that can push a tax deadline is a client that can tell every other device
/// the wrong one. A seam that cannot express a write is better than a shared
/// seam that can.
///
/// Read-only by construction: there is no write method here, and the server
/// has no policy that would accept one (see
/// `supabase/migrations/20260901160000_tax_calendar_overrides.sql`).
abstract class TaxOverrideRemoteDataSource {
  /// Every override published for [market].
  ///
  /// An empty list is a meaningful, expected answer — it says the shipped
  /// catalog stands — and is not distinguishable at this layer from "nothing
  /// has been published yet". Failure is thrown, not swallowed, so the caller
  /// can tell "the server says there are none" from "we could not ask".
  Future<List<Map<String, dynamic>>> fetchOverrides(String market);
}

/// [SupabaseClient]-backed implementation.
class SupabaseTaxOverrideRemoteDataSource
    implements TaxOverrideRemoteDataSource {
  const SupabaseTaxOverrideRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchOverrides(String market) async {
    // No session filter and no auth requirement: the RLS policy grants SELECT
    // to `anon` as well as `authenticated`, because the tax calendar is
    // generated for signed-out users too and they have no other channel.
    final List<dynamic> rows = await _client
        .from('tax_calendar_overrides')
        .select()
        .eq('market', market);
    return rows
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
}
