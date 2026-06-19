part of 'auth_bloc.dart';

/// Inputs to the [AuthBloc] state machine.
sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Fired once at app boot — resolves the session restored by
/// `supabase_flutter` on cold start.
final class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

/// Re-resolves the current session (e.g. after a deep-link callback lands).
final class AuthSessionRestored extends AuthEvent {
  const AuthSessionRestored();
}

/// Email + password sign-in.
final class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => <Object?>[email, password];
}

/// Email + password registration.
final class AuthSignUpRequested extends AuthEvent {
  const AuthSignUpRequested({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => <Object?>[email, password];
}

/// User-initiated sign out — also clears the local Drift cache.
final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// User-initiated account deletion — runs the server-side purge then clears
/// the local Drift cache, mirroring [AuthSignOutRequested].
final class AuthAccountDeletionRequested extends AuthEvent {
  const AuthAccountDeletionRequested();
}

/// Native Sign in with Apple.
final class AuthAppleRequested extends AuthEvent {
  const AuthAppleRequested();
}

/// Sends a password-reset email.
final class AuthPasswordResetRequested extends AuthEvent {
  const AuthPasswordResetRequested({required this.email});

  final String email;

  @override
  List<Object?> get props => <Object?>[email];
}

/// Internal — pushed by the Supabase session listener on every auth tick.
final class AuthStateChanged extends AuthEvent {
  const AuthStateChanged({this.user});

  final AppUser? user;

  @override
  List<Object?> get props => <Object?>[user];
}
