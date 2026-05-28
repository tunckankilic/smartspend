import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';

/// Hydrates a fresh `SplitSession` from the local Drift cache (Sprint 7).
///
/// Read-only contract — split state itself lives in `SplitBloc` and is
/// not persisted. The implementation does not write to Drift.
abstract class SplitRepository {
  /// Builds a `SplitSession` from a receipt + its line items. Returns
  /// [CacheFailure] when the receipt is missing locally (race condition
  /// — the user opened a deep link to a deleted receipt).
  Future<Either<Failure, SplitSession>> loadSession(int receiptId);
}
