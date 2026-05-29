import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';

/// Triggers a server-side CSV export of the user's expenses.
abstract class ExportRepository {
  /// Requests a CSV export, optionally bounded by [from]/[to] dates.
  Future<Either<Failure, ExportResult>> exportExpenses({
    DateTime? from,
    DateTime? to,
  });
}
