import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';

/// Generic use-case shape — one business action, returned via [Either].
abstract class UseCase<T, Params> {
  Future<Either<Failure, T>> call(Params params);
}

/// Sentinel for parameterless use cases (per CLAUDE.md).
class NoParams extends Equatable {
  const NoParams();

  @override
  List<Object?> get props => const <Object?>[];
}
