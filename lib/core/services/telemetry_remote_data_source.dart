// coverage:ignore-file
// PostgREST wrapper for telemetry uploads; the abstract seam is mocked in
// TelemetryService tests, the concrete impl is a thin SDK passthrough.
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin, mockable seam over the `product_events` table.
///
/// Deliberately separate from `SyncRemoteDataSource` rather than a method
/// added to it. That datasource's `upsert` resolves conflicts on the `id`
/// primary key, which is exactly the wrong key for a counter: it is what makes
/// two devices overwrite each other. Telemetry needs the natural key
/// `(user_id, device_id, event_key, dimension, day)`, and a seam that cannot
/// express the wrong one is better than a shared seam that can.
abstract class TelemetryRemoteDataSource {
  /// The authenticated user's id, or `null` when no session is active.
  String? get currentUserId;

  /// Upserts counter [rows] on the natural key.
  ///
  /// Each row carries the sending device's ABSOLUTE count for a day, so the
  /// server-side operation is an overwrite of that device's row only —
  /// idempotent under retry, and invisible to every other device's row.
  Future<void> upsertCounters(List<Map<String, dynamic>> rows);

  /// Deletes every counter belonging to the authenticated user.
  ///
  /// Opting out is an objection to processing, not merely a request to stop
  /// collecting more. Clearing only the device would leave everything already
  /// uploaded sitting on the server indefinitely — "off" has to reach what was
  /// already sent, or the switch is a promise about the future only.
  ///
  /// RLS already permits this: `product_events_delete_own` scopes DELETE to
  /// `auth.uid() = user_id`, so no elevated privilege is involved and the
  /// statement cannot touch anyone else's rows.
  Future<void> deleteAllForCurrentUser();
}

/// [SupabaseClient]-backed implementation. RLS scopes every write to the
/// authenticated user.
class SupabaseTelemetryRemoteDataSource implements TelemetryRemoteDataSource {
  const SupabaseTelemetryRemoteDataSource(this._client);

  final SupabaseClient _client;

  /// Must match the `product_events_identity_key` unique constraint exactly.
  /// A mismatch would not error — PostgREST would insert duplicates instead of
  /// updating, and the aggregate would silently inflate.
  static const String _conflictTarget =
      'user_id,device_id,event_key,dimension,day';

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> upsertCounters(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client
        .from('product_events')
        .upsert(rows, onConflict: _conflictTarget);
  }

  @override
  Future<void> deleteAllForCurrentUser() async {
    final String? userId = currentUserId;
    if (userId == null) return;
    // The filter is redundant under RLS and written anyway: a DELETE with no
    // WHERE is one policy misconfiguration away from being catastrophic, and
    // nothing about this call needs that much trust in the policy.
    await _client.from('product_events').delete().eq('user_id', userId);
  }
}
