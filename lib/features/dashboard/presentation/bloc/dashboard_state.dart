part of 'dashboard_bloc.dart';

/// Observable outputs of [DashboardBloc].
sealed class DashboardState extends Equatable {
  const DashboardState({required this.period});

  /// Current period so the chip row can highlight the right tile even
  /// while loading.
  final DashboardPeriod period;

  @override
  List<Object?> get props => <Object?>[period];
}

/// Pre-subscription.
final class DashboardInitial extends DashboardState {
  const DashboardInitial({
    super.period = const DashboardPeriod.thisMonth(),
  });
}

/// First snapshot pending — page-level spinner.
final class DashboardLoading extends DashboardState {
  const DashboardLoading({required super.period});
}

/// Steady state — every Drift emission lands here after the snapshot +
/// insight rebuild.
final class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    required super.period,
    required this.snapshot,
    required this.insight,
    required this.categories,
  });

  final DashboardSnapshot snapshot;
  final DashboardInsight? insight;

  /// Snapshot of all categories — used by widgets to render the pie /
  /// recent list without an extra lookup.
  final List<Category> categories;

  @override
  List<Object?> get props =>
      <Object?>[...super.props, snapshot, insight, categories];
}

/// Hard failure — repository couldn't produce a snapshot.
final class DashboardError extends DashboardState {
  const DashboardError({required super.period, required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[...super.props, failure];
}
