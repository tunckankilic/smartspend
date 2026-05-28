import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';

/// Sends a password-reset email (PKCE recovery link).
class ResetPasswordUseCase {
  const ResetPasswordUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<AuthFailure, Unit>> call(String email) =>
      _repository.resetPassword(email);
}
