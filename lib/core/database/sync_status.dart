/// Sync state tags stored in every syncable Drift row.
///
/// Drift columns are typed as `text` with these literal values so SQL filters
/// stay readable in the dashboard. Use these constants instead of bare strings
/// to keep refactors safe.
abstract class SyncStatus {
  SyncStatus._();

  /// Row matches the remote Supabase copy.
  static const String synced = 'synced';

  /// Row was created locally and has not yet been pushed to Supabase.
  static const String pendingCreate = 'pending_create';

  /// Row exists remotely; local edits await push.
  static const String pendingUpdate = 'pending_update';

  /// Row was deleted locally; once the delete propagates to Supabase the row
  /// is removed from Drift entirely.
  static const String pendingDelete = 'pending_delete';

  /// Local + remote diverged on the same field — flagged for manual or
  /// last-write-wins resolution by `SyncService`.
  static const String conflict = 'conflict';

  /// Statuses that the sync engine must push upstream.
  static const Set<String> pending = <String>{
    pendingCreate,
    pendingUpdate,
    pendingDelete,
  };
}

/// Tag values for [SyncLog.operation].
abstract class SyncOperation {
  SyncOperation._();

  static const String create = 'create';
  static const String update = 'update';
  static const String delete = 'delete';
  static const String pull = 'pull';

  /// Remote and local diverged; the engine kept the last writer by
  /// `updated_at` and logged the loser under this operation.
  static const String conflictResolved = 'conflict_resolved';
}
