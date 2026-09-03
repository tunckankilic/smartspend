// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/tax_reminder_scheduler.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

/// Which slice of the calendar the list is showing.
enum TaxCalendarRange {
  /// Deadlines in the current calendar month.
  thisMonth,

  /// The next three months, current month excluded.
  upcoming,

  /// Everything already past, newest first.
  past,
}

/// Observable state of the calendar screen.
sealed class TaxCalendarState extends Equatable {
  const TaxCalendarState({required this.range});

  /// The slice on screen. Carried on every state so the segmented control
  /// keeps its position through a reload.
  final TaxCalendarRange range;

  @override
  List<Object?> get props => <Object?>[range];
}

/// Before the first snapshot.
final class TaxCalendarLoading extends TaxCalendarState {
  const TaxCalendarLoading({super.range = TaxCalendarRange.thisMonth});
}

/// Steady state.
final class TaxCalendarLoaded extends TaxCalendarState {
  const TaxCalendarLoaded({
    required this.snapshot,
    required this.visible,
    required this.today,
    required super.range,
    this.transientError,
  });

  /// Everything the repository last emitted.
  final TaxCalendarSnapshot snapshot;

  /// The items in [TaxCalendarState.range], already sorted for display.
  final List<TaxCalendarItem> visible;

  /// The day the states were derived against. On screen because the states
  /// are derived, not stored — the list is only true as of this date.
  final DateTime today;

  /// Set when a write failed; cleared on the next snapshot.
  final Failure? transientError;

  /// Whether the user has told us anything at all yet.
  bool get hasProfile => snapshot.profile.answeredCount > 0;

  TaxCalendarLoaded copyWith({
    TaxCalendarSnapshot? snapshot,
    List<TaxCalendarItem>? visible,
    DateTime? today,
    TaxCalendarRange? range,
    Failure? transientError,
    bool clearTransientError = false,
  }) =>
      TaxCalendarLoaded(
        snapshot: snapshot ?? this.snapshot,
        visible: visible ?? this.visible,
        today: today ?? this.today,
        range: range ?? this.range,
        transientError:
            clearTransientError ? null : transientError ?? this.transientError,
      );

  @override
  List<Object?> get props => <Object?>[
        snapshot,
        visible,
        today,
        range,
        transientError,
      ];
}

/// The stream broke.
final class TaxCalendarError extends TaxCalendarState {
  const TaxCalendarError({
    required this.failure,
    super.range = TaxCalendarRange.thisMonth,
  });

  /// What went wrong.
  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure, range];
}

/// Owns the calendar screen.
///
/// Regenerates once on subscribe rather than only when the profile changes: a
/// month boundary brings new periods into range, and a user who opens the app
/// in November should not have to re-answer the wizard to see December.
class TaxCalendarCubit extends Cubit<TaxCalendarState> {
  TaxCalendarCubit({
    required TaxRepository repository,
    TaxReminderScheduler? reminders,
    DateTime Function()? clock,
  })  : _repository = repository,
        _reminders = reminders,
        _now = clock ?? DateTime.now,
        super(const TaxCalendarLoading());

  final TaxRepository _repository;

  /// Null wherever notifications are not part of the picture — tests, and any
  /// build without the scheduler wired. The calendar is fully usable without
  /// it; reminders are an addition to it, not a part of it.
  final TaxReminderScheduler? _reminders;

  final DateTime Function() _now;
  StreamSubscription<TaxCalendarSnapshot>? _subscription;

  /// Opens the stream and brings the generated window up to date.
  Future<void> subscribe() async {
    await _repository.regenerate();
    await _subscription?.cancel();
    _subscription = _repository.watchCalendar().listen(
          _onSnapshot,
          onError: (Object error) => emit(
            TaxCalendarError(
              failure: CacheFailure(message: error.toString()),
              range: state.range,
            ),
          ),
        );
    // Deliberately not awaited. The override pull is a network round trip and
    // the calendar must not wait on it — offline is the normal state, and a
    // screen that blanks until the network answers is a worse bug than a date
    // that is six hours stale. When it lands it regenerates, and the stream
    // above delivers the corrected dates on its own.
    unawaited(refreshOverrides());
  }

  /// Pulls published deadline corrections.
  ///
  /// Failure is swallowed on purpose: there is nothing the user can do about
  /// it and nothing is lost — the calendar keeps the dates it already had. The
  /// throttle lives in the repository, so calling this on every subscribe is
  /// cheap.
  ///
  /// 🚨 The `catch` is load-bearing, not defensive decoration. `subscribe()`
  /// launches this un-awaited, so a *thrown* error here — as opposed to a
  /// `Left`, which the repository returns for the failures it anticipates —
  /// becomes an unhandled async error rather than a swallowed one, and takes
  /// down the zone that happens to be running. Returning a Left is the
  /// contract; surviving a breach of it is this method's job.
  Future<void> refreshOverrides({bool force = false}) async {
    try {
      await _repository.refreshOverrides(force: force);
    } on Object {
      // Deliberately empty: see above. A calendar the user can read beats a
      // correction they cannot receive.
    }
  }

  /// Brings the scheduled reminders back in line with what is on screen.
  ///
  /// Called from the page rather than from [subscribe] because the language is
  /// a property of the widget tree and the notification text is composed from
  /// it. Cheap to call on every rebuild: the scheduler compares the plan
  /// against what it last scheduled and does nothing when they match.
  ///
  /// This is what makes marking a return filed take its reminder away
  /// promptly. Without it the next reminder would still fire, and a
  /// notification telling someone to file what they have already filed is the
  /// one that gets notifications switched off.
  Future<void> refreshReminders({required String languageCode}) async {
    final TaxReminderScheduler? scheduler = _reminders;
    if (scheduler == null) {
      return;
    }
    try {
      await scheduler.tick(languageCode: languageCode);
    } on Object {
      // Nothing the user can act on, and nothing lost: the previously
      // scheduled set stands until the next successful tick.
    }
  }

  /// Switches the visible slice.
  void showRange(TaxCalendarRange range) {
    final TaxCalendarState current = state;
    if (current is! TaxCalendarLoaded) {
      emit(TaxCalendarLoading(range: range));
      return;
    }
    emit(
      current.copyWith(
        range: range,
        visible: _filter(current.snapshot.items, range),
      ),
    );
  }

  void _onSnapshot(TaxCalendarSnapshot snapshot) {
    emit(
      TaxCalendarLoaded(
        snapshot: snapshot,
        visible: _filter(snapshot.items, state.range),
        today: _today(),
        range: state.range,
      ),
    );
  }

  DateTime _today() {
    final DateTime now = _now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// Selects and sorts the items for [range].
  ///
  /// Dismissed items are dropped from every slice — the user said they do not
  /// apply — but the row is kept, so the signal survives and the next
  /// regeneration does not resurrect them.
  ///
  /// Items with no known deadline fall into [TaxCalendarRange.thisMonth] by
  /// their period rather than disappearing: a dateless obligation is the norm
  /// while the catalog is unverified, and it has to be somewhere the user can
  /// find it.
  List<TaxCalendarItem> _filter(
    List<TaxCalendarItem> items,
    TaxCalendarRange range,
  ) {
    final DateTime today = _today();
    final DateTime monthStart = DateTime.utc(today.year, today.month);
    final DateTime monthEnd = DateTime.utc(today.year, today.month + 1, 0);
    final DateTime upcomingEnd = DateTime.utc(today.year, today.month + 4, 0);

    bool inRange(TaxCalendarItem item) {
      final DateTime? due = item.nextDueDate;
      switch (range) {
        case TaxCalendarRange.thisMonth:
          if (due == null) {
            return !item.periodEnd.isBefore(monthStart) &&
                !item.periodStart.isAfter(monthEnd);
          }
          return !due.isBefore(monthStart) && !due.isAfter(monthEnd);
        case TaxCalendarRange.upcoming:
          return due != null &&
              due.isAfter(monthEnd) &&
              !due.isAfter(upcomingEnd);
        case TaxCalendarRange.past:
          return item.stateAt(today) == TaxObligationState.completed ||
              (due != null && due.isBefore(monthStart));
      }
    }

    final List<TaxCalendarItem> selected = items
        .where((TaxCalendarItem i) => i.dismissedAt == null)
        .where(inRange)
        .toList()
      ..sort((TaxCalendarItem a, TaxCalendarItem b) {
        final DateTime? da = a.nextDueDate;
        final DateTime? db = b.nextDueDate;
        if (da != null && db != null && da != db) {
          return range == TaxCalendarRange.past
              ? db.compareTo(da)
              : da.compareTo(db);
        }
        // Dateless items sort after dated ones rather than jumping to the
        // top: they are real, but they are not what the user has to act on
        // this week.
        if (da == null && db != null) {
          return 1;
        }
        if (da != null && db == null) {
          return -1;
        }
        return a.periodStart.compareTo(b.periodStart);
      });
    return selected;
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
