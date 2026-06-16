import 'package:dartz/dartz.dart';

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/daos/user_correction_dao.dart';
import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';
import 'package:smartspend/features/categorization/domain/repositories/user_correction_repository.dart';

/// Drift-backed [UserCorrectionRepository].
///
/// `drift_db` alias avoids the name clash between the domain
/// `UserCorrection` (a value object) and Drift's generated `UserCorrection`
/// data class (a row representation).
class UserCorrectionRepositoryImpl implements UserCorrectionRepository {
  const UserCorrectionRepositoryImpl({required this.dao});

  final UserCorrectionDao dao;

  UserCorrectionDao get _dao => dao;

  @override
  Future<Either<Failure, Unit>> record(UserCorrection correction) async {
    try {
      await _dao.upsertCorrection(
        storeName: correction.storeName,
        oldCategoryId: correction.oldCategoryId,
        newCategoryId: correction.newCategoryId,
        occurredAt: correction.occurredAt.toUtc(),
      );
      return const Right<Failure, Unit>(unit);
    } on CacheException catch (e) {
      return Left<Failure, Unit>(CacheFailure(message: e.message));
    } on Object catch (e) {
      return Left<Failure, Unit>(CacheFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, UserCorrection?>> topForStore(
    String storeName,
  ) async {
    try {
      final drift_db.UserCorrection? row =
          await _dao.getTopCorrectionForStore(storeName);
      if (row == null) {
        return const Right<Failure, UserCorrection?>(null);
      }
      return Right<Failure, UserCorrection?>(
        UserCorrection(
          storeName: row.storeName,
          oldCategoryId: row.oldCategoryId,
          newCategoryId: row.newCategoryId,
          occurredAt: row.occurredAt,
        ),
      );
    } on CacheException catch (e) {
      return Left<Failure, UserCorrection?>(CacheFailure(message: e.message));
    } on Object catch (e) {
      return Left<Failure, UserCorrection?>(
        CacheFailure(message: e.toString()),
      );
    }
  }
}
