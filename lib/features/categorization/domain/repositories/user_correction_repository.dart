import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';

/// Persistence boundary for [UserCorrection]s.
///
/// Sprint 6 introduces this contract — the data-layer implementation
/// wraps the new `user_corrections` Drift table. Sprint 8 will extend
/// the implementation with Supabase push/pull while the domain
/// interface stays unchanged.
abstract class UserCorrectionRepository {
  /// Records (or increments the count of) a correction in local storage.
  ///
  /// Implementations MUST be idempotent on `(storeName, newCategoryId)`
  /// so that a re-applied correction does not produce duplicate rows.
  Future<Either<Failure, Unit>> record(UserCorrection correction);

  /// Returns the strongest learned override for [storeName], or `null`
  /// when the user has never overridden anything for that store.
  ///
  /// "Strongest" = the row with the highest `count`, breaking ties by
  /// most recent `occurredAt`.
  Future<Either<Failure, UserCorrection?>> topForStore(String storeName);
}
