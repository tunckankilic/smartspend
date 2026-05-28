// Private-field naming convention — see BudgetBloc for the same
// pattern. Explicit `_loadSession = loadSession` reads cleaner than
// the initializing-formal shorthand when paired with documentation.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/domain/usecases/load_split_session.dart';
import 'package:smartspend/features/split/domain/usecases/split_calculator.dart';

part 'split_event.dart';
part 'split_state.dart';

/// State machine for `SplitPage` (Sprint 7).
///
/// Page-scoped (factory in DI, mirrors BudgetBloc / DashboardBloc). The
/// session lives only as long as this bloc — closing the page disposes
/// it. The bloc never writes to Drift / Supabase; the prompt explicitly
/// scopes Split as ephemeral.
///
/// Math lives in [SplitCalculator] (pure function). The bloc's only
/// responsibilities are:
///   1. seed `SplitSession` from the repository,
///   2. apply user mutations (participants, assignments, mode toggle),
///   3. recompute `perPersonMinor` on every mutation,
///   4. format + emit a share string when requested.
class SplitBloc extends Bloc<SplitEvent, SplitState> {
  SplitBloc({
    required LoadSplitSessionUseCase loadSession,
    required SplitShareSink shareSink,
  })  : _loadSession = loadSession,
        _shareSink = shareSink,
        super(const SplitInitial()) {
    on<SplitStarted>(_onStarted, transformer: droppable());
    on<SplitParticipantAdded>(_onParticipantAdded, transformer: sequential());
    on<SplitParticipantRemoved>(
      _onParticipantRemoved,
      transformer: sequential(),
    );
    on<SplitItemAssigned>(_onItemAssigned, transformer: sequential());
    on<SplitTypeChanged>(_onTypeChanged, transformer: sequential());
    on<SplitShareRequested>(_onShareRequested, transformer: droppable());
  }

  final LoadSplitSessionUseCase _loadSession;
  final SplitShareSink _shareSink;

  /// Monotonic counter for synthetic participant ids ("p1", "p2", ...).
  /// Kept on the bloc so re-adding after a remove gets a fresh id and
  /// can't accidentally inherit a stale item-assignment list.
  int _nextParticipantSeq = 0;

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  Future<void> _onStarted(
    SplitStarted event,
    Emitter<SplitState> emit,
  ) async {
    emit(const SplitLoading());
    final Either<Failure, SplitSession> result =
        await _loadSession(LoadSplitSessionParams(receiptId: event.receiptId));
    result.fold(
      (Failure f) => emit(SplitError(failure: f)),
      (SplitSession session) => emit(
        SplitLoaded(
          session: session,
          perPersonMinor: const <String, int>{},
        ),
      ),
    );
  }

  Future<void> _onParticipantAdded(
    SplitParticipantAdded event,
    Emitter<SplitState> emit,
  ) async {
    final SplitState s = state;
    if (s is! SplitLoaded) return;
    final String name = event.name.trim();
    if (name.isEmpty) return;
    final String id = 'p${++_nextParticipantSeq}';
    final List<Participant> next = <Participant>[
      ...s.session.participants,
      Participant(id: id, name: name),
    ];
    _emitRebuilt(emit, s.session.copyWith(participants: next));
  }

  Future<void> _onParticipantRemoved(
    SplitParticipantRemoved event,
    Emitter<SplitState> emit,
  ) async {
    final SplitState s = state;
    if (s is! SplitLoaded) return;
    final List<Participant> next = s.session.participants
        .where((Participant p) => p.id != event.participantId)
        .toList(growable: false);
    final Map<int, List<String>> nextAssignments = <int, List<String>>{
      for (final MapEntry<int, List<String>> entry
          in s.session.assignments.entries)
        entry.key: entry.value
            .where((String id) => id != event.participantId)
            .toList(growable: false),
    }..removeWhere((int _, List<String> ids) => ids.isEmpty);
    _emitRebuilt(
      emit,
      s.session.copyWith(
        participants: next,
        assignments: nextAssignments,
      ),
    );
  }

  Future<void> _onItemAssigned(
    SplitItemAssigned event,
    Emitter<SplitState> emit,
  ) async {
    final SplitState s = state;
    if (s is! SplitLoaded) return;
    final Map<int, List<String>> next =
        Map<int, List<String>>.from(s.session.assignments);
    if (event.participantIds.isEmpty) {
      next.remove(event.itemId);
    } else {
      next[event.itemId] = List<String>.unmodifiable(event.participantIds);
    }
    _emitRebuilt(emit, s.session.copyWith(assignments: next));
  }

  Future<void> _onTypeChanged(
    SplitTypeChanged event,
    Emitter<SplitState> emit,
  ) async {
    final SplitState s = state;
    if (s is! SplitLoaded) return;
    if (s.session.splitType == event.type) return;
    _emitRebuilt(emit, s.session.copyWith(splitType: event.type));
  }

  Future<void> _onShareRequested(
    SplitShareRequested event,
    Emitter<SplitState> emit,
  ) async {
    final SplitState s = state;
    if (s is! SplitLoaded) return;
    if (s.session.participants.isEmpty) return;
    try {
      await _shareSink.share(event.payload);
      emit(s.copyWith(clearTransient: true));
    } on Object catch (e) {
      emit(
        s.copyWith(
          transientFailure:
              UnexpectedFailure(message: e.toString(), code: 'SPLIT_SHARE'),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Recompute helper
  // -------------------------------------------------------------------------

  void _emitRebuilt(Emitter<SplitState> emit, SplitSession session) {
    final Map<String, int> totals = SplitCalculator.calculate(
      participants: session.participants,
      items: session.items,
      assignments: session.assignments,
      type: session.splitType,
      totalMinor: session.totalMinor,
    );
    emit(
      SplitLoaded(session: session, perPersonMinor: totals),
    );
  }
}

/// Side-effect boundary for the platform share sheet. `share_plus` is
/// injected via a thin adapter so unit tests can pass a fake and assert
/// on payloads without invoking native code.
abstract class SplitShareSink {
  Future<void> share(String text);
}
