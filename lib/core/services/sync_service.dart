import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';

/// Drift ⇄ Supabase reconciliation engine.
///
/// The client is offline-first: repositories read and write Drift
/// unconditionally, stamping rows with a `pending_*` [SyncStatus]. This
/// service drains that queue ([push]) and folds remote changes back into
/// the local cache ([pull]) whenever the network is available. It owns no
/// UI; the [SyncIndicator] subscribes to [watchStatus].
abstract class SyncService {
  /// Pulls remote rows changed since the last watermark into Drift,
  /// resolving conflicts last-write-wins by `updated_at`.
  Future<Either<Failure, SyncReport>> pull();

  /// Pushes every locally `pending_*` row to Supabase in foreign-key order,
  /// stamping successes as `synced` and logging failures to `sync_log`.
  Future<Either<Failure, SyncReport>> push();

  /// Convenience: [push] then [pull]. Returns the merged report. A push
  /// failure short-circuits before the pull so the caller sees the first
  /// error.
  Future<Either<Failure, SyncReport>> sync();

  /// Number of local rows still waiting to be pushed to Supabase. Read at
  /// sign-out to warn before the local cache is wiped — anything still
  /// pending would otherwise be lost permanently by the wipe.
  Future<int> pendingCount();

  /// Broadcast stream of the current [SyncPhase] for the status indicator.
  Stream<SyncPhase> watchStatus();

  /// Starts connectivity + periodic foreground triggers. Idempotent.
  void start();

  /// Tears down listeners and timers. Call on app shutdown / sign-out.
  Future<void> dispose();
}

/// Tally of what a [SyncService.push] / [SyncService.pull] / [SyncService.sync]
/// run moved, surfaced for logging and tests.
class SyncReport extends Equatable {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.failed = 0,
  });

  /// Rows successfully upserted to Supabase.
  final int pushed;

  /// Remote rows folded into Drift.
  final int pulled;

  /// Rows where remote and local diverged; resolved last-write-wins.
  final int conflicts;

  /// Rows whose push failed and were left `pending_*` for the next run.
  final int failed;

  /// Sums two reports — used to merge the push leg into the pull leg.
  SyncReport operator +(SyncReport other) => SyncReport(
    pushed: pushed + other.pushed,
    pulled: pulled + other.pulled,
    conflicts: conflicts + other.conflicts,
    failed: failed + other.failed,
  );

  @override
  List<Object?> get props => <Object?>[pushed, pulled, conflicts, failed];
}

/// UI-facing snapshot of the sync engine's state. Distinct from the
/// row-level `SyncStatus` string constants stored in Drift.
sealed class SyncPhase extends Equatable {
  const SyncPhase();

  @override
  List<Object?> get props => <Object?>[];
}

/// Everything is reconciled. [lastSyncAt] is `null` before the first sync.
class SyncPhaseSynced extends SyncPhase {
  const SyncPhaseSynced({this.lastSyncAt});

  final DateTime? lastSyncAt;

  @override
  List<Object?> get props => <Object?>[lastSyncAt];
}

/// A push/pull run is in flight.
class SyncPhaseSyncing extends SyncPhase {
  const SyncPhaseSyncing();
}

/// [count] local rows are waiting to be pushed (network down, or run failed).
class SyncPhasePending extends SyncPhase {
  const SyncPhasePending({required this.count});

  final int count;

  @override
  List<Object?> get props => <Object?>[count];
}

/// No connectivity; the engine is parked until the network returns.
class SyncPhaseOffline extends SyncPhase {
  const SyncPhaseOffline();
}
