import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/data/datasources/supabase_auth_data_source.dart';
import 'package:smartspend/features/auth/data/repositories/supabase_auth_repository_impl.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';

class _MockDataSource extends Mock implements SupabaseAuthDataSource {}

void main() {
  const AppUser tUser = AppUser(id: 'u1', email: 'me@real.com');

  late _MockDataSource dataSource;
  late SupabaseAuthRepositoryImpl repository;

  setUp(() {
    dataSource = _MockDataSource();
    repository = SupabaseAuthRepositoryImpl(dataSource: dataSource);
  });

  group('SupabaseAuthRepositoryImpl', () {
    test('signIn returns Right(AppUser) on success', () async {
      when(
        () => dataSource.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => tUser);

      final Either<AuthFailure, AppUser> result = await repository.signIn(
        email: 'me@real.com',
        password: 'pw',
      );

      expect(result, equals(const Right<AuthFailure, AppUser>(tUser)));
    });

    test(
      'signIn maps AuthException(invalid_credentials) to AuthFailure',
      () async {
        when(
          () => dataSource.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(const AuthException('bad', code: 'invalid_credentials'));

        final Either<AuthFailure, AppUser> result = await repository.signIn(
          email: 'me@real.com',
          password: 'pw',
        );

        expect(
          result.fold((AuthFailure f) => f.code, (_) => null),
          AuthFailureCode.invalidCredentials,
        );
      },
    );

    test('signUp maps a retryable fetch error to the network code', () async {
      when(
        () => dataSource.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(AuthRetryableFetchException(message: 'offline'));

      final Either<AuthFailure, AppUser> result = await repository.signUp(
        email: 'me@real.com',
        password: 'pw',
      );

      expect(
        result.fold((AuthFailure f) => f.code, (_) => null),
        AuthFailureCode.network,
      );
    });

    test('signOut returns Right(unit) on success', () async {
      when(() => dataSource.signOut()).thenAnswer((_) async {});

      final Either<AuthFailure, Unit> result = await repository.signOut();

      expect(result, equals(const Right<AuthFailure, Unit>(unit)));
    });

    test('resetPassword maps an unknown error to the unknown code', () async {
      when(
        () => dataSource.resetPassword(any()),
      ).thenThrow(const AuthException('boom'));

      final Either<AuthFailure, Unit> result = await repository.resetPassword(
        'me@real.com',
      );

      expect(
        result.fold((AuthFailure f) => f.code, (_) => null),
        AuthFailureCode.unknown,
      );
    });
  });
}
