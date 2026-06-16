part of 'sync_cubit.dart';

/// UI state for the sync engine, derived from [SyncPhase] plus the conflict
/// signal that the phase stream doesn't carry.
sealed class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => <Object?>[];
}

/// Before the first phase arrives.
class SyncIdle extends SyncState {
  const SyncIdle();
}

/// A push/pull run is in flight.
class SyncInProgress extends SyncState {
  const SyncInProgress();
}

/// Everything reconciled. [lastSyncAt] is `null` before the first sync.
class SyncSynced extends SyncState {
  const SyncSynced({this.lastSyncAt});

  final DateTime? lastSyncAt;

  @override
  List<Object?> get props => <Object?>[lastSyncAt];
}

/// [count] local rows are waiting to be pushed.
class SyncPending extends SyncState {
  const SyncPending({required this.count});

  final int count;

  @override
  List<Object?> get props => <Object?>[count];
}

/// The last run failed outright (not a per-row failure).
class SyncFailed extends SyncState {
  const SyncFailed({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

/// No connectivity; the engine is parked until the network returns.
class SyncOffline extends SyncState {
  const SyncOffline();
}

/// The last run resolved [count] conflicts last-write-wins — surfaced once so
/// the UI can inform the user their local edits may have been overwritten.
class SyncConflict extends SyncState {
  const SyncConflict({required this.count});

  final int count;

  @override
  List<Object?> get props => <Object?>[count];
}
