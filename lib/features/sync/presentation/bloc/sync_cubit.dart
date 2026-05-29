import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/sync_service.dart';

part 'sync_state.dart';

/// Presentation-layer owner of the Drift ⇄ Supabase sync engine.
///
/// The widget tree talks to *this* — never to [SyncService] directly — so the
/// "no service calls from widgets" rule holds. It mirrors the engine's
/// [SyncService.watchStatus] phase stream into a [SyncState], surfaces manual
/// syncs via [syncNow], and re-triggers a sync whenever connectivity is
/// restored. Registered as a singleton so the AppBar chip, the offline banner,
/// and the conflict listener all share one stream subscription.
class SyncCubit extends Cubit<SyncState> {
  SyncCubit({
    required this.service,
    required this.connectivity,
  }) : super(const SyncIdle());

  final SyncService service;
  final Connectivity connectivity;

  StreamSubscription<SyncPhase>? _phaseSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _started = false;

  /// Subscribes to the engine's phase stream and connectivity changes.
  /// Idempotent — safe to call from both `main` and the widget tree.
  void start() {
    if (_started) return;
    _started = true;
    _phaseSub = service.watchStatus().listen(_onPhase);
    _connSub = connectivity.onConnectivityChanged.listen(_onConnectivity);
  }

  /// Runs a full push+pull. A conflict count surfaces as a transient
  /// [SyncConflict] (consumers show a banner/snackbar); the phase stream then
  /// settles the chip back to synced/pending. Failures become [SyncFailed].
  Future<void> syncNow() async {
    final Either<Failure, SyncReport> result = await service.sync();
    result.fold(
      (Failure failure) => _safeEmit(SyncFailed(failure: failure)),
      (SyncReport report) {
        if (report.conflicts > 0) {
          _safeEmit(SyncConflict(count: report.conflicts));
        }
      },
    );
  }

  void _onPhase(SyncPhase phase) {
    _safeEmit(switch (phase) {
      SyncPhaseSyncing() => const SyncInProgress(),
      SyncPhaseOffline() => const SyncOffline(),
      SyncPhasePending(:final int count) => SyncPending(count: count),
      SyncPhaseSynced(:final DateTime? lastSyncAt) =>
        SyncSynced(lastSyncAt: lastSyncAt),
    });
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final bool online = results.any(
      (ConnectivityResult r) => r != ConnectivityResult.none,
    );
    if (online) await syncNow();
  }

  void _safeEmit(SyncState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> close() async {
    await _phaseSub?.cancel();
    await _connSub?.cancel();
    return super.close();
  }
}
