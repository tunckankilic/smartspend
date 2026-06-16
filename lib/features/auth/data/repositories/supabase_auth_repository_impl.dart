// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/failure_codes.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/data/datasources/supabase_auth_data_source.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';

class SupabaseAuthRepositoryImpl implements AuthRepository {
  const SupabaseAuthRepositoryImpl({required SupabaseAuthDataSource dataSource})
      : _dataSource = dataSource;

  final SupabaseAuthDataSource _dataSource;

  @override
  Stream<AppUser?> authStateChanges() => _dataSource.authStateChanges();

  @override
  AppUser? currentUser() => _dataSource.currentUser();

  @override
  Future<Either<AuthFailure, AppUser>> signIn({
    required String email,
    required String password,
  }) {
    return _guard(
      () => _dataSource.signInWithPassword(email: email, password: password),
    );
  }

  @override
  Future<Either<AuthFailure, AppUser>> signUp({
    required String email,
    required String password,
  }) {
    return _guard(
      () => _dataSource.signUp(email: email, password: password),
    );
  }

  @override
  Future<Either<AuthFailure, AppUser>> signInWithGoogle() =>
      _guard(_dataSource.signInWithGoogle);

  @override
  Future<Either<AuthFailure, AppUser>> signInWithApple() =>
      _guard(_dataSource.signInWithApple);

  @override
  Future<Either<AuthFailure, Unit>> signOut() {
    return _guardUnit(_dataSource.signOut);
  }

  @override
  Future<Either<AuthFailure, Unit>> resetPassword(String email) {
    return _guardUnit(() => _dataSource.resetPassword(email));
  }

  @override
  Future<Either<AuthFailure, Unit>> deleteAccount() {
    return _guardUnit(_dataSource.deleteAccount);
  }

  Future<Either<AuthFailure, AppUser>> _guard(
    Future<AppUser> Function() action,
  ) async {
    try {
      return Right<AuthFailure, AppUser>(await action());
    } on Object catch (error) {
      return Left<AuthFailure, AppUser>(_mapError(error));
    }
  }

  Future<Either<AuthFailure, Unit>> _guardUnit(
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return const Right<AuthFailure, Unit>(unit);
    } on Object catch (error) {
      return Left<AuthFailure, Unit>(_mapError(error));
    }
  }

  AuthFailure _mapError(Object error) {
    if (error is AuthRetryableFetchException) {
      return AuthFailure(message: error.message, code: AuthFailureCode.network);
    }
    if (error is AuthException) {
      final String? code = error.code;
      final String mapped = switch (code) {
        'invalid_credentials' ||
        'invalid_grant' =>
          AuthFailureCode.invalidCredentials,
        'email_not_confirmed' => AuthFailureCode.emailNotConfirmed,
        'user_already_exists' ||
        'email_exists' =>
          AuthFailureCode.userExists,
        'weak_password' => AuthFailureCode.weakPassword,
        _ => AuthFailureCode.unknown,
      };
      return AuthFailure(message: error.message, code: mapped);
    }
    if (error is PostgrestException) {
      return AuthFailure(message: error.message, code: AuthFailureCode.unknown);
    }
    if (error is FunctionException) {
      // Edge Function returned a non-2xx envelope (e.g. delete-account). The
      // body carries our {error:{code,message}} shape; keep the message for
      // logs only and surface a generic code.
      return AuthFailure(
        message: 'Edge Function error (status ${error.status}).',
        code: AuthFailureCode.unknown,
      );
    }
    if (error is TimeoutException) {
      return const AuthFailure(
        message: 'Network timeout during authentication.',
        code: AuthFailureCode.network,
      );
    }
    return AuthFailure(
      message: error.toString(),
      code: AuthFailureCode.unknown,
    );
  }
}
