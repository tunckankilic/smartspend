// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/telemetry_service.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

/// Adds a deadline the user tracks themselves.
///
/// Records `tax_item_custom_added`, the third of the three signals about
/// whether the generated calendar fits: dismissals say we produced something
/// wrong, edits say we produced something nearly right, and this says we
/// missed something entirely.
class AddCustomTaxItemUseCase
    implements UseCase<int, AddCustomTaxItemParams> {
  const AddCustomTaxItemUseCase({
    required TaxRepository repository,
    required TelemetryService telemetry,
  })  : _repository = repository,
        _telemetry = telemetry;

  final TaxRepository _repository;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, int>> call(AddCustomTaxItemParams params) async {
    final String title = params.title.trim();
    if (title.isEmpty) {
      // Same shape as the expenses repository's own guards: a validation
      // refusal is a CacheFailure with a code the UI can switch on.
      return const Left<Failure, int>(
        CacheFailure(message: 'title must not be empty', code: 'title_empty'),
      );
    }

    final Either<Failure, int> result = await _repository.addCustomItem(
      title: title,
      dueDate: params.dueDate,
      isPayment: params.isPayment,
      note: params.note,
    );
    if (result.isRight()) {
      await _telemetry.record(ProductEvent.taxItemCustomAdded);
    }
    return result;
  }
}

class AddCustomTaxItemParams extends Equatable {
  const AddCustomTaxItemParams({
    required this.title,
    required this.dueDate,
    this.isPayment = true,
    this.note,
  });

  /// The user's name for the deadline.
  final String title;

  /// When it is due.
  final DateTime dueDate;

  /// Whether the deadline is a payment (the default) or a filing.
  final bool isPayment;

  /// Optional note.
  final String? note;

  @override
  List<Object?> get props => <Object?>[title, dueDate, isPayment, note];
}
