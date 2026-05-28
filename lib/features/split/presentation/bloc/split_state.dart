part of 'split_bloc.dart';

/// Output surface of [SplitBloc].
sealed class SplitState extends Equatable {
  const SplitState();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Pre-load state — the bloc has been constructed but `SplitStarted`
/// hasn't been dispatched yet.
final class SplitInitial extends SplitState {
  const SplitInitial();
}

/// Receipt is being read out of Drift.
final class SplitLoading extends SplitState {
  const SplitLoading();
}

/// Steady state — session loaded, totals recalculated on every event.
///
/// `perPersonMinor` is keyed by `Participant.id` for stable lookup;
/// the UI projects it back to display order using `session.participants`.
/// `transientFailure` surfaces non-fatal errors (e.g. share-sheet
/// dismissed) without dropping the session.
final class SplitLoaded extends SplitState {
  const SplitLoaded({
    required this.session,
    required this.perPersonMinor,
    this.transientFailure,
  });

  final SplitSession session;
  final Map<String, int> perPersonMinor;
  final Failure? transientFailure;

  SplitLoaded copyWith({
    SplitSession? session,
    Map<String, int>? perPersonMinor,
    Failure? transientFailure,
    bool clearTransient = false,
  }) {
    return SplitLoaded(
      session: session ?? this.session,
      perPersonMinor: perPersonMinor ?? this.perPersonMinor,
      transientFailure:
          clearTransient ? null : (transientFailure ?? this.transientFailure),
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[session, perPersonMinor, transientFailure];
}

/// Fatal load failure — receipt missing, Drift unavailable, etc. The UI
/// shows a retry CTA.
final class SplitError extends SplitState {
  const SplitError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
