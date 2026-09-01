// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/core/services/telemetry_service.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

/// Saves the taxpayer profile, regenerates the calendar, and — when the save
/// came from the wizard — records the one measurement 1.3.0 exists for.
///
/// `tax_profile_completed` broken down by legal form is what answers D-2: who
/// the ICP actually is. It fires on wizard completion **including when the
/// user skipped the question**, because `belirtilmedi` is an answer about the
/// step, not a missing data point. It does not fire on later edits from
/// settings — those would count the same person again and tilt the
/// distribution towards whoever fiddles with their profile.
class SaveTaxProfileUseCase
    implements UseCase<void, SaveTaxProfileParams> {
  const SaveTaxProfileUseCase({
    required TaxRepository repository,
    required TelemetryService telemetry,
  })  : _repository = repository,
        _telemetry = telemetry;

  final TaxRepository _repository;
  final TelemetryService _telemetry;

  @override
  Future<Either<Failure, void>> call(SaveTaxProfileParams params) async {
    final Either<Failure, void> result =
        await _repository.saveProfile(params.profile);
    if (result.isRight() && params.fromWizard) {
      await _telemetry.record(
        ProductEvent.taxProfileCompleted,
        dimension: params.profile.legalForm.telemetryDimension,
      );
    }
    return result;
  }
}

class SaveTaxProfileParams extends Equatable {
  const SaveTaxProfileParams({
    required this.profile,
    this.fromWizard = false,
  });

  /// The eight answers, however many of them were given.
  final TaxpayerProfile profile;

  /// True when the user reached the end of the wizard, which is the only
  /// moment the D-2 counter is allowed to move.
  final bool fromWizard;

  @override
  List<Object?> get props => <Object?>[profile, fromWizard];
}
