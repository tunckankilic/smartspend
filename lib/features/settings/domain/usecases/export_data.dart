import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';
import 'package:smartspend/features/settings/domain/repositories/export_repository.dart';

/// Requests a server-side CSV export of the user's expenses.
class ExportDataUseCase implements UseCase<ExportResult, ExportParams> {
  const ExportDataUseCase(this._repository);

  final ExportRepository _repository;

  @override
  Future<Either<Failure, ExportResult>> call(ExportParams params) {
    return _repository.exportExpenses(from: params.from, to: params.to);
  }
}

/// Optional date bounds for the export.
class ExportParams extends Equatable {
  const ExportParams({this.from, this.to});

  final DateTime? from;
  final DateTime? to;

  @override
  List<Object?> get props => <Object?>[from, to];
}
