import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';

/// Native Google Sign-In → Supabase `signInWithIdToken`.
class GoogleSignInUseCase {
  const GoogleSignInUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<AuthFailure, AppUser>> call() =>
      _repository.signInWithGoogle();
}
