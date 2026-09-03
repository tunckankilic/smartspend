// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/services/telemetry_service.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

/// Edits an item's note, amount or dates.
///
/// 🚨 [TaxAmountSource] has no value meaning "the app calculated this", so
/// this use case cannot record one either. Every amount that reaches the row
/// was typed by a person and says which person.
///
/// Records `tax_item_edited`: a user correcting a generated item is evidence
/// that the catalog is off for them, which is the same question the dismissal
/// counter asks from the other side.
class AnnotateTaxObligationUseCase
    implements UseCase<void, AnnotateTaxObligationParams> {
  const AnnotateTaxObligationUseCase({
    required TaxRepository repository,
    required TelemetryService telemetry,
  })  : _repository = repository,
        _telemetry = telemetry;

  final TaxRepository _repository;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, void>> call(
    AnnotateTaxObligationParams params,
  ) async {
    Either<Failure, void> result = const Right<Failure, void>(null);

    if (params.editsNote) {
      result = await _repository.setNote(params.id, params.note);
    }
    if (result.isRight() && params.editsAmount) {
      result = await _repository.setAmount(
        params.id,
        amountMinor: params.amountMinor,
        source: params.amountSource ?? TaxAmountSource.unknown,
      );
    }
    if (result.isRight() && params.editsDueDates) {
      result = await _repository.setUserDueDates(
        params.id,
        declarationDueDate: params.declarationDueDate,
        paymentDueDate: params.paymentDueDate,
      );
    }

    if (result.isRight()) {
      await _telemetry.record(ProductEvent.taxItemEdited);
    }
    return result;
  }
}

class AnnotateTaxObligationParams extends Equatable {
  const AnnotateTaxObligationParams({
    required this.id,
    this.note,
    this.editsNote = false,
    this.amountMinor,
    this.amountSource,
    this.editsAmount = false,
    this.declarationDueDate,
    this.paymentDueDate,
    this.editsDueDates = false,
  });

  /// Local row id.
  final int id;

  /// The note, or null to clear it. Only written when [editsNote].
  final String? note;

  /// Whether this call touches the note at all.
  ///
  /// A separate flag rather than "null means leave alone", because clearing a
  /// note is a thing the user does and it must be distinguishable from not
  /// mentioning it.
  final bool editsNote;

  /// The amount in the smallest currency unit, or null to clear it.
  final int? amountMinor;

  /// Who says so.
  final TaxAmountSource? amountSource;

  /// Whether this call touches the amount.
  final bool editsAmount;

  /// The user's own filing deadline.
  final DateTime? declarationDueDate;

  /// The user's own payment deadline.
  final DateTime? paymentDueDate;

  /// Whether this call replaces the deadlines with the user's own.
  final bool editsDueDates;

  @override
  List<Object?> get props => <Object?>[
        id,
        note,
        editsNote,
        amountMinor,
        amountSource,
        editsAmount,
        declarationDueDate,
        paymentDueDate,
        editsDueDates,
      ];
}
