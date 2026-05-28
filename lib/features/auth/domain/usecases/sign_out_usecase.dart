import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';

/// Ends the Supabase session. Local cache clearing is the [AuthBloc]'s job
/// once this resolves.
class SignOutUseCase {
  const SignOutUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<AuthFailure, Unit>> call() => _repository.signOut();
}
