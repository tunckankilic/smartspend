import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';

/// Email + password registration. The returned [AppUser] may still need to
/// confirm their email before a session is active (see [AuthBloc]).
class SignUpUseCase {
  const SignUpUseCase(this._repository);

  final AuthRepository _repository;

  Future<Either<AuthFailure, AppUser>> call(SignUpParams params) {
    return _repository.signUp(
      email: params.email,
      password: params.password,
    );
  }
}

class SignUpParams extends Equatable {
  const SignUpParams({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => <Object?>[email, password];
}
