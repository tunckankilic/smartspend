import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';

/// Native Sign in with Apple → Supabase `signInWithIdToken`. iOS-only at the
/// UI level; the use case itself is platform-agnostic.
class AppleSignInUseCase {
  const AppleSignInUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<AuthFailure, AppUser>> call() => _repository.signInWithApple();
}
