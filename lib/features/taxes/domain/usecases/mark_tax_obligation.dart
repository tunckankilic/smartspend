// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/telemetry_service.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

/// Which of the three marks is being set.
enum TaxObligationMark {
  /// The user filed it.
  declared,

  /// The user paid it.
  paid,

  /// The user says it does not apply to them.
  dismissed,
}

/// Sets or clears one mark on one calendar item.
///
/// Filing and paying are separate marks on purpose — they are separate acts,
/// usually days apart — so there is no "done" here to collapse them into.
///
/// Dismissing records `tax_item_removed`, which is the sharpest product signal
/// this release collects: it says the generated calendar is wrong for this
/// taxpayer. Undismissing does not record anything, because a user correcting
/// a misclick is not evidence about the catalog.
class MarkTaxObligationUseCase
    implements UseCase<void, MarkTaxObligationParams> {
  const MarkTaxObligationUseCase({
    required TaxRepository repository,
    required TelemetryService telemetry,
  })  : _repository = repository,
        _telemetry = telemetry;

  final TaxRepository _repository;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, void>> call(MarkTaxObligationParams params) async {
    final Either<Failure, void> result = switch (params.mark) {
      TaxObligationMark.declared =>
        await _repository.setDeclared(params.id, params.at),
      TaxObligationMark.paid =>
        await _repository.setPaid(params.id, params.at),
      TaxObligationMark.dismissed =>
        await _repository.setDismissed(params.id, params.at),
    };

    if (result.isRight() &&
        params.mark == TaxObligationMark.dismissed &&
        params.at != null) {
      await _telemetry.record(ProductEvent.taxItemRemoved);
    }
    return result;
  }
}

class MarkTaxObligationParams extends Equatable {
  const MarkTaxObligationParams({
    required this.id,
    required this.mark,
    required this.at,
  });

  /// Local row id.
  final int id;

  /// Which mark.
  final TaxObligationMark mark;

  /// When it happened, or null to take the mark back.
  final DateTime? at;

  @override
  List<Object?> get props => <Object?>[id, mark, at];
}
