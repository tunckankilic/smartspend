import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/auth/domain/entities/auth_user.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';

void main() {
  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      final AuthBloc bloc = AuthBloc();
      expect(bloc.state, isA<AuthInitial>());
      bloc.close();
    });

    blocTest<AuthBloc, AuthState>(
      'AuthStarted should emit [AuthLoading, Authenticated(devUser)]',
      build: AuthBloc.new,
      act: (AuthBloc bloc) => bloc.add(const AuthStarted()),
      expect: () => <Matcher>[
        isA<AuthLoading>(),
        isA<Authenticated>(),
      ],
      verify: (AuthBloc bloc) {
        final AuthState state = bloc.state;
        expect(state, isA<Authenticated>());
        expect((state as Authenticated).user.email, 'dev@smartspend.local');
      },
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSignedOutRequested should emit [AuthLoading, Unauthenticated]',
      build: AuthBloc.new,
      seed: () => const Authenticated(
        user: AuthUser(id: 'u1', email: 'a@b.com'),
      ),
      act: (AuthBloc bloc) => bloc.add(const AuthSignedOutRequested()),
      expect: () => <Matcher>[
        isA<AuthLoading>(),
        isA<Unauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSessionChanged(null) should emit Unauthenticated',
      build: AuthBloc.new,
      act: (AuthBloc bloc) =>
          bloc.add(const AuthSessionChanged()),
      expect: () => <Matcher>[isA<Unauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthSessionChanged(user) should emit Authenticated(user)',
      build: AuthBloc.new,
      act: (AuthBloc bloc) => bloc.add(
        const AuthSessionChanged(
          user: AuthUser(id: 'real', email: 'me@real.com'),
        ),
      ),
      expect: () => <Matcher>[isA<Authenticated>()],
      verify: (AuthBloc bloc) {
        expect((bloc.state as Authenticated).user.id, 'real');
      },
    );
  });
}
