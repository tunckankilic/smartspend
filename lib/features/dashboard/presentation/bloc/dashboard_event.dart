part of 'dashboard_bloc.dart';

/// Inbound events for [DashboardBloc]. Past-tense per CLAUDE.md.
sealed class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Open the underlying watch stream — fired by the page on first mount.
/// Idempotent: re-subscribing tears down the previous stream.
final class DashboardSubscribed extends DashboardEvent {
  const DashboardSubscribed();
}

/// User picked a different period chip (or custom range). The bloc
/// re-subscribes against the new filter and re-runs the snapshot
/// pipeline.
final class DashboardPeriodChanged extends DashboardEvent {
  const DashboardPeriodChanged({required this.period});

  final DashboardPeriod period;

  @override
  List<Object?> get props => <Object?>[period];
}

/// Pull-to-refresh from the page. Sprint 8 will pump the sync worker
/// before re-querying; Sprint 5 just re-subscribes Drift.
final class DashboardRefreshed extends DashboardEvent {
  const DashboardRefreshed();
}

/// Internal: a snapshot landed on the watch stream — rebuild the
/// payload. Private so widgets can't dispatch it.
final class _DashboardWatchTicked extends DashboardEvent {
  const _DashboardWatchTicked();
}

/// Internal: the watch stream blew up. Surfaces as [DashboardError].
final class _DashboardWatchErrored extends DashboardEvent {
  const _DashboardWatchErrored(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
