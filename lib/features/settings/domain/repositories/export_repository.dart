import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';

/// Triggers a server-side export of the user's expenses (CSV or PDF).
abstract class ExportRepository {
  /// Requests an export in [format], optionally bounded by [from]/[to] dates.
  Future<Either<Failure, ExportResult>> exportExpenses({
    DateTime? from,
    DateTime? to,
    ExportFormat format,
  });
}
