import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/data/datasources/export_remote_data_source.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';
import 'package:smartspend/features/settings/domain/repositories/export_repository.dart';

class ExportRepositoryImpl implements ExportRepository {
  const ExportRepositoryImpl(this._remote);

  final ExportRemoteDataSource _remote;

  @override
  Future<Either<Failure, ExportResult>> exportExpenses({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final ExportResult result = await _remote.exportExpenses(
        from: from,
        to: to,
      );
      return Right<Failure, ExportResult>(result);
    } on ServerException catch (e) {
      return Left<Failure, ExportResult>(ServerFailure(message: e.message));
    } on Exception catch (e) {
      return Left<Failure, ExportResult>(
        ServerFailure(message: 'Export failed: $e'),
      );
    }
  }
}
