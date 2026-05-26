part of 'auth_bloc.dart';

/// Inputs to the [AuthBloc] state machine.
sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Fired once at app boot — resolves the current session.
final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// User-initiated sign out.
final class AuthSignedOutRequested extends AuthEvent {
  const AuthSignedOutRequested();
}

/// Internal — pushed by the real Supabase session listener (Sprint 8).
final class AuthSessionChanged extends AuthEvent {
  const AuthSessionChanged({this.user});

  final AuthUser? user;

  @override
  List<Object?> get props => <Object?>[user];
}
