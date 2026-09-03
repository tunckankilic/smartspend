// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';
import 'package:smartspend/features/taxes/domain/usecases/annotate_tax_obligation.dart';
import 'package:smartspend/features/taxes/domain/usecases/mark_tax_obligation.dart';

/// Observable state of the item detail screen.
class TaxObligationDetailState extends Equatable {
  const TaxObligationDetailState({
    required this.today,
    this.item,
    this.isLoading = true,
    this.failure,
  });

  /// The item, once loaded.
  final TaxCalendarItem? item;

  /// The day the derived state is computed against.
  final DateTime today;

  /// First load in flight.
  final bool isLoading;

  /// Last write or load failure.
  final Failure? failure;

  /// The item's state as of [today] — derived on every build, never stored.
  TaxObligationState? get itemState => item?.stateAt(today);

  TaxObligationDetailState copyWith({
    TaxCalendarItem? item,
    DateTime? today,
    bool? isLoading,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      TaxObligationDetailState(
        item: item ?? this.item,
        today: today ?? this.today,
        isLoading: isLoading ?? this.isLoading,
        failure: clearFailure ? null : failure ?? this.failure,
      );

  @override
  List<Object?> get props => <Object?>[item, today, isLoading, failure];
}

/// Owns the item detail screen.
///
/// Every write re-reads the row rather than patching the state in place. The
/// screen's headline is a *derived* value, and deriving it from a
/// hand-assembled local copy is how the two drift apart.
class TaxObligationDetailCubit extends Cubit<TaxObligationDetailState> {
  TaxObligationDetailCubit({
    required TaxRepository repository,
    required MarkTaxObligationUseCase mark,
    required AnnotateTaxObligationUseCase annotate,
    DateTime Function()? clock,
  })  : _repository = repository,
        _mark = mark,
        _annotate = annotate,
        _now = clock ?? DateTime.now,
        super(
          TaxObligationDetailState(
            today: _todayFrom((clock ?? DateTime.now)()),
          ),
        );

  final TaxRepository _repository;
  final MarkTaxObligationUseCase _mark;
  final AnnotateTaxObligationUseCase _annotate;
  final DateTime Function() _now;

  static DateTime _todayFrom(DateTime now) {
    final DateTime utc = now.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// Loads the item.
  Future<void> load(int id) async {
    emit(state.copyWith(isLoading: true, clearFailure: true));
    final Either<Failure, TaxCalendarItem?> result =
        await _repository.getItem(id);
    result.fold(
      (Failure f) => emit(state.copyWith(isLoading: false, failure: f)),
      (TaxCalendarItem? item) => emit(
        TaxObligationDetailState(
          item: item,
          today: _todayFrom(_now()),
          isLoading: false,
        ),
      ),
    );
  }

  /// Marks the item filed, or clears the mark.
  ///
  /// Filing is not paying: this never touches the payment mark.
  Future<void> setDeclared({required bool declared}) => _applyMark(
        TaxObligationMark.declared,
        declared ? _now().toUtc() : null,
      );

  /// Marks the item paid, or clears the mark.
  Future<void> setPaid({required bool paid}) =>
      _applyMark(TaxObligationMark.paid, paid ? _now().toUtc() : null);

  /// Says the item does not apply to this taxpayer, or takes that back.
  Future<void> setDismissed({required bool dismissed}) => _applyMark(
        TaxObligationMark.dismissed,
        dismissed ? _now().toUtc() : null,
      );

  /// Saves the user's note.
  Future<void> setNote(String? note) async {
    final TaxCalendarItem? item = state.item;
    if (item == null) {
      return;
    }
    final String? trimmed =
        (note == null || note.trim().isEmpty) ? null : note.trim();
    await _run(
      _annotate(
        AnnotateTaxObligationParams(
          id: item.id,
          note: trimmed,
          editsNote: true,
        ),
      ),
      item.id,
    );
  }

  /// Saves an amount and who said it.
  ///
  /// [source] can never be "the app worked it out" — that value does not
  /// exist. Clearing the amount resets the source to unknown rather than
  /// leaving a claim behind with no number attached to it.
  Future<void> setAmount({
    required int? amountMinor,
    required TaxAmountSource source,
  }) async {
    final TaxCalendarItem? item = state.item;
    if (item == null) {
      return;
    }
    await _run(
      _annotate(
        AnnotateTaxObligationParams(
          id: item.id,
          amountMinor: amountMinor,
          amountSource: amountMinor == null ? TaxAmountSource.unknown : source,
          editsAmount: true,
        ),
      ),
      item.id,
    );
  }

  /// Replaces the deadlines with the user's own.
  Future<void> setUserDueDates({
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
  }) async {
    final TaxCalendarItem? item = state.item;
    if (item == null) {
      return;
    }
    await _run(
      _annotate(
        AnnotateTaxObligationParams(
          id: item.id,
          declarationDueDate: declarationDueDate,
          paymentDueDate: paymentDueDate,
          editsDueDates: true,
        ),
      ),
      item.id,
    );
  }

  Future<void> _applyMark(TaxObligationMark mark, DateTime? at) async {
    final TaxCalendarItem? item = state.item;
    if (item == null) {
      return;
    }
    await _run(
      _mark(MarkTaxObligationParams(id: item.id, mark: mark, at: at)),
      item.id,
    );
  }

  Future<void> _run(Future<Either<Failure, void>> action, int id) async {
    final Either<Failure, void> result = await action;
    await result.fold(
      (Failure f) async => emit(state.copyWith(failure: f)),
      (_) => load(id),
    );
  }
}
