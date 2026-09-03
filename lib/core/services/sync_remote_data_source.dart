// coverage:ignore-file
// PostgREST query-builder wrapper for the sync engine; the abstract seam is
// mocked in SyncService tests, the concrete impl is a thin SDK passthrough.
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin, mockable seam over the Supabase table API used by the sync engine.
///
/// The engine speaks in plain `Map<String, dynamic>` rows and snake_case
/// column names; this datasource is the only place that touches the raw
/// [SupabaseClient] query builder, so tests mock this interface instead of
/// the (hard-to-fake) PostgREST builder chain.
abstract class SyncRemoteDataSource {
  /// The authenticated user's id, or `null` when no session is active.
  ///
  /// Push stamps this onto every row's `user_id` so Postgres RLS
  /// (`auth.uid() = user_id`) accepts the write — locally created rows are
  /// born without an owner and would otherwise be rejected.
  String? get currentUserId;

  /// Upserts [values] into [table] and returns the server-assigned `id`.
  /// Omit `id` from [values] to insert a fresh row and let Postgres generate
  /// the UUID.
  ///
  /// Conflicts resolve on the `id` primary key unless [onConflict] names
  /// another unique constraint (comma-separated columns). That matters for
  /// rows a second device can recreate independently rather than pull: a
  /// taxpayer profile filled offline on a tablet has no `id` to conflict on,
  /// and without a target the insert would either duplicate the row or fail
  /// forever against the table's unique key.
  Future<String> upsert(
    String table,
    Map<String, dynamic> values, {
    String? onConflict,
  });

  /// Fetches every row in [table] whose `updated_at` is strictly greater
  /// than [since]. A `null` [since] pulls the full table (first sync).
  Future<List<Map<String, dynamic>>> fetchSince(String table, DateTime? since);

  /// Deletes the row identified by [id] from [table].
  Future<void> deleteById(String table, String id);
}

/// [SupabaseClient]-backed implementation. RLS scopes every query to the
/// authenticated user, so no explicit `user_id` filter is needed here.
class SupabaseSyncRemoteDataSource implements SyncRemoteDataSource {
  const SupabaseSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<String> upsert(
    String table,
    Map<String, dynamic> values, {
    String? onConflict,
  }) async {
    final Map<String, dynamic> row = await _client
        .from(table)
        .upsert(values, onConflict: onConflict)
        .select('id')
        .single();
    return row['id'] as String;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSince(
    String table,
    DateTime? since,
  ) async {
    final PostgrestFilterBuilder<PostgrestList> query = _client
        .from(table)
        .select();
    final PostgrestList rows = since == null
        ? await query
        : await query.gt('updated_at', since.toUtc().toIso8601String());
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> deleteById(String table, String id) {
    return _client.from(table).delete().eq('id', id);
  }
}
