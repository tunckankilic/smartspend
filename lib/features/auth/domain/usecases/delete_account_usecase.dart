import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';

/// Irreversibly deletes the caller's account server-side and ends the local
/// session. Local cache clearing is the [AuthBloc]'s job once this resolves.
class DeleteAccountUseCase {
  const DeleteAccountUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<AuthFailure, Unit>> call() => _repository.deleteAccount();
}
