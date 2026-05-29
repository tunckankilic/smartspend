import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';
import 'package:smartspend/features/auth/domain/usecases/apple_sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/delete_account_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/google_sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/reset_password_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_up_usecase.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repo;

  const AppUser user = AppUser(id: 'u1', email: 'a@b.com');
  const AuthFailure failure = AuthFailure(message: 'nope');

  setUp(() {
    repo = _MockAuthRepository();
  });

  group('SignInUseCase', () {
    test('should forward email/password and return the user', () async {
      when(() => repo.signIn(email: 'a@b.com', password: 'pw'))
          .thenAnswer((_) async => const Right<AuthFailure, AppUser>(user));

      final SignInUseCase usecase = SignInUseCase(repo);
      final Either<AuthFailure, AppUser> result = await usecase(
        const SignInParams(email: 'a@b.com', password: 'pw'),
      );

      expect(result, const Right<AuthFailure, AppUser>(user));
      verify(() => repo.signIn(email: 'a@b.com', password: 'pw')).called(1);
    });

    test('should propagate a repository failure', () async {
      when(
        () => repo.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => const Left<AuthFailure, AppUser>(failure));

      final Either<AuthFailure, AppUser> result = await SignInUseCase(repo)(
        const SignInParams(email: 'a@b.com', password: 'pw'),
      );

      expect(result, const Left<AuthFailure, AppUser>(failure));
    });

    test('SignInParams props include email and password', () {
      expect(
        const SignInParams(email: 'a@b.com', password: 'pw'),
        const SignInParams(email: 'a@b.com', password: 'pw'),
      );
    });
  });

  group('SignUpUseCase', () {
    test('should forward email/password and return the user', () async {
      when(() => repo.signUp(email: 'a@b.com', password: 'pw'))
          .thenAnswer((_) async => const Right<AuthFailure, AppUser>(user));

      final Either<AuthFailure, AppUser> result = await SignUpUseCase(repo)(
        const SignUpParams(email: 'a@b.com', password: 'pw'),
      );

      expect(result, const Right<AuthFailure, AppUser>(user));
      verify(() => repo.signUp(email: 'a@b.com', password: 'pw')).called(1);
    });

    test('SignUpParams props include email and password', () {
      expect(
        const SignUpParams(email: 'a@b.com', password: 'pw'),
        const SignUpParams(email: 'a@b.com', password: 'pw'),
      );
    });
  });

  group('GoogleSignInUseCase', () {
    test('should delegate to signInWithGoogle', () async {
      when(repo.signInWithGoogle)
          .thenAnswer((_) async => const Right<AuthFailure, AppUser>(user));

      final Either<AuthFailure, AppUser> result =
          await GoogleSignInUseCase(repo)();

      expect(result, const Right<AuthFailure, AppUser>(user));
      verify(repo.signInWithGoogle).called(1);
    });
  });

  group('AppleSignInUseCase', () {
    test('should delegate to signInWithApple', () async {
      when(repo.signInWithApple)
          .thenAnswer((_) async => const Right<AuthFailure, AppUser>(user));

      final Either<AuthFailure, AppUser> result =
          await AppleSignInUseCase(repo)();

      expect(result, const Right<AuthFailure, AppUser>(user));
      verify(repo.signInWithApple).called(1);
    });
  });

  group('SignOutUseCase', () {
    test('should delegate to signOut', () async {
      when(repo.signOut)
          .thenAnswer((_) async => const Right<AuthFailure, Unit>(unit));

      final Either<AuthFailure, Unit> result = await SignOutUseCase(repo)();

      expect(result, const Right<AuthFailure, Unit>(unit));
      verify(repo.signOut).called(1);
    });
  });

  group('DeleteAccountUseCase', () {
    test('should delegate to deleteAccount', () async {
      when(repo.deleteAccount)
          .thenAnswer((_) async => const Right<AuthFailure, Unit>(unit));

      final Either<AuthFailure, Unit> result =
          await DeleteAccountUseCase(repo)();

      expect(result, const Right<AuthFailure, Unit>(unit));
      verify(repo.deleteAccount).called(1);
    });
  });

  group('ResetPasswordUseCase', () {
    test('should forward the email', () async {
      when(() => repo.resetPassword('a@b.com'))
          .thenAnswer((_) async => const Right<AuthFailure, Unit>(unit));

      final Either<AuthFailure, Unit> result =
          await ResetPasswordUseCase(repo)('a@b.com');

      expect(result, const Right<AuthFailure, Unit>(unit));
      verify(() => repo.resetPassword('a@b.com')).called(1);
    });
  });
}
