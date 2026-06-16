part of 'auth_bloc.dart';

/// Observable outputs of [AuthBloc]. The router listens to this stream to
/// pick between authenticated and unauthenticated route trees.
sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => <Object?>[];
}

/// Before the first session resolve completes.
final class AuthInitial extends AuthState {
  const AuthInitial();
}

/// An auth action (sign-in, sign-up, sign-out, reset) is in flight.
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// A session is active.
final class Authenticated extends AuthState {
  const Authenticated({required this.user});

  final AppUser user;

  @override
  List<Object?> get props => <Object?>[user];
}

/// No active session — covers cold start, sign-out, and unconfirmed sign-up.
final class Unauthenticated extends AuthState {
  const Unauthenticated();
}

/// The last auth action failed. Holds the base [Failure]; presentation maps
/// the [Failure.code] onto a localized message.
final class AuthFailure extends AuthState {
  const AuthFailure(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
