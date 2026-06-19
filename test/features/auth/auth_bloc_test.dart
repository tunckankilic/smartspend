import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart' as failures;
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';
import 'package:smartspend/features/auth/domain/usecases/apple_sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/delete_account_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/reset_password_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_up_usecase.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';

import '../../helpers/test_database.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockSignInUseCase extends Mock implements SignInUseCase {}

class _MockSignUpUseCase extends Mock implements SignUpUseCase {}

class _MockSignOutUseCase extends Mock implements SignOutUseCase {}

class _MockDeleteAccountUseCase extends Mock
    implements DeleteAccountUseCase {}

class _MockAppleSignInUseCase extends Mock implements AppleSignInUseCase {}

class _MockResetPasswordUseCase extends Mock implements ResetPasswordUseCase {}

void main() {
  const AppUser tUser = AppUser(id: 'u1', email: 'me@real.com');
  const failures.AuthFailure tFailure = failures.AuthFailure(
    message: 'bad creds',
    code: 'invalid_credentials',
  );

  late _MockAuthRepository repository;
  late _MockSignInUseCase signIn;
  late _MockSignUpUseCase signUp;
  late _MockSignOutUseCase signOut;
  late _MockDeleteAccountUseCase deleteAccount;
  late _MockAppleSignInUseCase appleSignIn;
  late _MockResetPasswordUseCase resetPassword;
  late AppDatabase database;
  late StreamController<AppUser?> authStream;

  setUpAll(() {
    registerFallbackValue(
      const SignInParams(email: 'a@b.com', password: 'x'),
    );
    registerFallbackValue(
      const SignUpParams(email: 'a@b.com', password: 'x'),
    );
  });

  setUp(() {
    repository = _MockAuthRepository();
    signIn = _MockSignInUseCase();
    signUp = _MockSignUpUseCase();
    signOut = _MockSignOutUseCase();
    deleteAccount = _MockDeleteAccountUseCase();
    appleSignIn = _MockAppleSignInUseCase();
    resetPassword = _MockResetPasswordUseCase();
    database = createTestDatabase();
    authStream = StreamController<AppUser?>.broadcast();

    when(
      () => repository.authStateChanges(),
    ).thenAnswer((_) => authStream.stream);
    when(() => repository.currentUser()).thenReturn(null);
  });

  tearDown(() async {
    await authStream.close();
    await database.close();
  });

  AuthBloc build() => AuthBloc(
    authRepository: repository,
    signIn: signIn,
    signUp: signUp,
    signOut: signOut,
    deleteAccount: deleteAccount,
    appleSignIn: appleSignIn,
    resetPassword: resetPassword,
    database: database,
  );

  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      final AuthBloc bloc = build();
      expect(bloc.state, isA<AuthInitial>());
      bloc.close();
    });

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested emits Unauthenticated when no session',
      build: build,
      act: (AuthBloc bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => <Matcher>[isA<Unauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthCheckRequested emits Authenticated when a session exists',
      build: build,
      setUp: () => when(() => repository.currentUser()).thenReturn(tUser),
      act: (AuthBloc bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => <Matcher>[isA<Authenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignInRequested success emits [AuthLoading, Authenticated]',
      build: build,
      setUp: () => when(() => signIn(any())).thenAnswer(
        (_) async => const Right<failures.AuthFailure, AppUser>(tUser),
      ),
      act: (AuthBloc bloc) => bloc.add(
        const AuthSignInRequested(email: 'me@real.com', password: 'pw'),
      ),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<Authenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignInRequested failure emits [AuthLoading, AuthFailure]',
      build: build,
      setUp: () => when(() => signIn(any())).thenAnswer(
        (_) async => const Left<failures.AuthFailure, AppUser>(tFailure),
      ),
      act: (AuthBloc bloc) => bloc.add(
        const AuthSignInRequested(email: 'me@real.com', password: 'pw'),
      ),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<AuthFailure>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignUpRequested without session emits [AuthLoading, '
      'Unauthenticated] (email confirmation pending)',
      build: build,
      setUp: () {
        when(() => signUp(any())).thenAnswer(
          (_) async => const Right<failures.AuthFailure, AppUser>(tUser),
        );
        when(() => repository.currentUser()).thenReturn(null);
      },
      act: (AuthBloc bloc) => bloc.add(
        const AuthSignUpRequested(email: 'me@real.com', password: 'pw'),
      ),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<Unauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignOutRequested success emits [AuthLoading, Unauthenticated] '
      'and clears the local cache',
      build: build,
      setUp: () => when(
        () => signOut(),
      ).thenAnswer((_) async => const Right<failures.AuthFailure, Unit>(unit)),
      act: (AuthBloc bloc) => bloc.add(const AuthSignOutRequested()),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<Unauthenticated>()],
      verify: (_) => verify(() => signOut()).called(1),
    );

    blocTest<AuthBloc, AuthState>(
      'AuthAccountDeletionRequested success emits [AuthLoading, '
      'Unauthenticated] and clears the local cache',
      build: build,
      setUp: () => when(() => deleteAccount()).thenAnswer(
        (_) async => const Right<failures.AuthFailure, Unit>(unit),
      ),
      act: (AuthBloc bloc) =>
          bloc.add(const AuthAccountDeletionRequested()),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<Unauthenticated>()],
      verify: (_) => verify(() => deleteAccount()).called(1),
    );

    blocTest<AuthBloc, AuthState>(
      'AuthAccountDeletionRequested failure emits [AuthLoading, AuthFailure]',
      build: build,
      setUp: () => when(() => deleteAccount()).thenAnswer(
        (_) async => const Left<failures.AuthFailure, Unit>(tFailure),
      ),
      act: (AuthBloc bloc) =>
          bloc.add(const AuthAccountDeletionRequested()),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<AuthFailure>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthAppleRequested success emits [AuthLoading, Authenticated]',
      build: build,
      setUp: () => when(() => appleSignIn()).thenAnswer(
        (_) async => const Right<failures.AuthFailure, AppUser>(tUser),
      ),
      act: (AuthBloc bloc) => bloc.add(const AuthAppleRequested()),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<Authenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthPasswordResetRequested success emits [AuthLoading, '
      'Unauthenticated]',
      build: build,
      setUp: () => when(
        () => resetPassword(any()),
      ).thenAnswer((_) async => const Right<failures.AuthFailure, Unit>(unit)),
      act: (AuthBloc bloc) => bloc.add(
        const AuthPasswordResetRequested(email: 'me@real.com'),
      ),
      expect: () => <Matcher>[isA<AuthLoading>(), isA<Unauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'session stream tick with a user emits Authenticated',
      build: build,
      act: (AuthBloc bloc) => authStream.add(tUser),
      expect: () => <Matcher>[isA<Authenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'session stream tick with null emits Unauthenticated',
      build: build,
      act: (AuthBloc bloc) => authStream.add(null),
      expect: () => <Matcher>[isA<Unauthenticated>()],
    );
  });
}
