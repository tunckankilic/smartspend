// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';

class RecordUserCorrectionParams extends Equatable {
  const RecordUserCorrectionParams({required this.correction});

  final UserCorrection correction;

  @override
  List<Object?> get props => <Object?>[correction];
}

/// Persists a [UserCorrection] for later use by the categorizer.
///
/// Sprint 4 forwards corrections to the structured logger (and via the
/// BlocObserver to Sentry breadcrumbs) so we have a paper trail before
/// the dedicated `user_corrections` Drift table lands in Sprint 6.
class RecordUserCorrectionUseCase {
  const RecordUserCorrectionUseCase({required Logger logger})
      : _logger = logger;

  final Logger _logger;

  Future<Either<Failure, void>> call(
    RecordUserCorrectionParams params,
  ) async {
    final UserCorrection c = params.correction;
    _logger.i(
      'categorization.correction store="${c.storeName}" '
      'oldId=${c.oldCategoryId} → newId=${c.newCategoryId}',
    );
    return const Right<Failure, void>(null);
  }
}
