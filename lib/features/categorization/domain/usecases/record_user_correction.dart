// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';
import 'package:smartspend/features/categorization/domain/repositories/user_correction_repository.dart';

class RecordUserCorrectionParams extends Equatable {
  const RecordUserCorrectionParams({required this.correction});

  final UserCorrection correction;

  @override
  List<Object?> get props => <Object?>[correction];
}

/// Persists a [UserCorrection] for later use by the categorizer.
///
/// Sprint 4 forwarded corrections to the structured logger only — the
/// dedicated `user_corrections` Drift table landed in Sprint 6, so the
/// use case now writes through the [UserCorrectionRepository] AND keeps
/// the breadcrumb log line for Sentry forensics. Sprint 8 will pump the
/// pending rows to Supabase via the standard sync queue.
class RecordUserCorrectionUseCase {
  const RecordUserCorrectionUseCase({
    required UserCorrectionRepository repository,
    required Logger logger,
  })  : _repository = repository,
        _logger = logger;

  final UserCorrectionRepository _repository;
  final Logger _logger;

  Future<Either<Failure, void>> call(
    RecordUserCorrectionParams params,
  ) async {
    final UserCorrection c = params.correction;
    _logger.i(
      'categorization.correction store="${c.storeName}" '
      'oldId=${c.oldCategoryId} → newId=${c.newCategoryId}',
    );
    final Either<Failure, Unit> result = await _repository.record(c);
    return result.fold(
      (Failure f) {
        _logger.w(
          'categorization.correction persist-failed: ${f.message}',
        );
        return Left<Failure, void>(f);
      },
      (_) => const Right<Failure, void>(null),
    );
  }
}
