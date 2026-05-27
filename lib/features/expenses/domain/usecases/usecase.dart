import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';

/// Generic use-case shape — one business action, returned via [Either].
///
/// This mirrors `features/scan/domain/usecases/usecase.dart`; once Sprint
/// 4 adds more features that depend on the same shape, both copies will
/// be replaced by a single `lib/core/usecases/usecase.dart` and the local
/// re-exports dropped. Until then, keeping it feature-local avoids
/// rippling Sprint 2 imports.
abstract class UseCase<T, Params> {
  Future<Either<Failure, T>> call(Params params);
}

class NoParams extends Equatable {
  const NoParams();

  @override
  List<Object?> get props => const <Object?>[];
}
