// Private-field naming + default-resolved `now` make initializing
// formals awkward; keep explicit field bindings (matches BudgetBloc).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:stream_transform/stream_transform.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/domain/usecases/watch_receipt_archive.dart';

part 'receipt_archive_event.dart';
part 'receipt_archive_state.dart';

/// Page-scoped state machine for `ReceiptArchivePage` (Sprint 7).
///
/// Stays in lock-step with Drift via a single `watchArchive` stream.
/// On filter or search change the bloc re-subscribes (via the
/// `restartable()` transformer on the private tick handler) so the
/// underlying stream only ever has one listener at a time.
class ReceiptArchiveBloc
    extends Bloc<ReceiptArchiveEvent, ReceiptArchiveState> {
  ReceiptArchiveBloc({required WatchReceiptArchiveUseCase watchArchive})
      : _watchArchive = watchArchive,
        super(const ReceiptArchiveInitial()) {
    on<ReceiptArchiveSubscribed>(_onSubscribed, transformer: droppable());
    on<ReceiptArchiveSearchChanged>(
      _onSearchChanged,
      transformer: (
        Stream<ReceiptArchiveSearchChanged> events,
        Stream<ReceiptArchiveSearchChanged> Function(
          ReceiptArchiveSearchChanged,
        ) mapper,
      ) {
        return events
            .debounce(const Duration(milliseconds: 300))
            .switchMap(mapper);
      },
    );
    on<ReceiptArchiveDateRangeChanged>(
      _onDateRangeChanged,
      transformer: sequential(),
    );
    on<ReceiptArchiveViewToggled>(_onViewToggled);
    on<_ReceiptArchiveTicked>(_onTicked, transformer: restartable());
    on<_ReceiptArchiveStreamErrored>(_onErrored);
  }

  final WatchReceiptArchiveUseCase _watchArchive;
  StreamSubscription<List<ReceiptArchiveEntry>>? _archiveSub;

  ReceiptArchiveFilter _filter = ReceiptArchiveFilter.empty;
  ReceiptArchiveLayout _layout = ReceiptArchiveLayout.grid;

  @override
  Future<void> close() async {
    await _archiveSub?.cancel();
    return super.close();
  }

  // ---------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------

  Future<void> _onSubscribed(
    ReceiptArchiveSubscribed event,
    Emitter<ReceiptArchiveState> emit,
  ) async {
    emit(const ReceiptArchiveLoading());
    await _resubscribe();
  }

  Future<void> _onSearchChanged(
    ReceiptArchiveSearchChanged event,
    Emitter<ReceiptArchiveState> emit,
  ) async {
    final String trimmed = event.query.trim();
    _filter = _filter.copyWith(
      searchQuery: trimmed.isEmpty ? null : trimmed,
      clearSearchQuery: trimmed.isEmpty,
    );
    await _resubscribe();
  }

  Future<void> _onDateRangeChanged(
    ReceiptArchiveDateRangeChanged event,
    Emitter<ReceiptArchiveState> emit,
  ) async {
    _filter = _filter.copyWith(
      from: event.from,
      to: event.to,
      clearFrom: event.from == null,
      clearTo: event.to == null,
    );
    await _resubscribe();
  }

  void _onViewToggled(
    ReceiptArchiveViewToggled event,
    Emitter<ReceiptArchiveState> emit,
  ) {
    _layout = _layout == ReceiptArchiveLayout.grid
        ? ReceiptArchiveLayout.list
        : ReceiptArchiveLayout.grid;
    final ReceiptArchiveState s = state;
    if (s is ReceiptArchiveLoaded) {
      emit(s.copyWith(layout: _layout));
    }
  }

  void _onTicked(
    _ReceiptArchiveTicked event,
    Emitter<ReceiptArchiveState> emit,
  ) {
    emit(
      ReceiptArchiveLoaded(
        entries: event.entries,
        filter: _filter,
        layout: _layout,
      ),
    );
  }

  void _onErrored(
    _ReceiptArchiveStreamErrored event,
    Emitter<ReceiptArchiveState> emit,
  ) {
    emit(ReceiptArchiveError(failure: event.failure));
  }

  // ---------------------------------------------------------------------
  // Subscription plumbing
  // ---------------------------------------------------------------------

  Future<void> _resubscribe() async {
    await _archiveSub?.cancel();
    _archiveSub = _watchArchive(_filter).listen(
      (List<ReceiptArchiveEntry> rows) {
        add(_ReceiptArchiveTicked(rows));
      },
      onError: (Object e, StackTrace _) {
        add(
          _ReceiptArchiveStreamErrored(CacheFailure(message: e.toString())),
        );
      },
    );
  }
}
