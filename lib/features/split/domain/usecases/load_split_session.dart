import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/repositories/split_repository.dart';

/// Hydrates a fresh `SplitSession` for the given receipt (Sprint 7).
class LoadSplitSessionUseCase
    implements UseCase<SplitSession, LoadSplitSessionParams> {
  const LoadSplitSessionUseCase(this._repository);

  final SplitRepository _repository;

  @override
  Future<Either<Failure, SplitSession>> call(LoadSplitSessionParams params) {
    return _repository.loadSession(params.receiptId);
  }
}

class LoadSplitSessionParams extends Equatable {
  const LoadSplitSessionParams({required this.receiptId});

  final int receiptId;

  @override
  List<Object?> get props => <Object?>[receiptId];
}
