part of 'auth_bloc.dart';

/// Observable outputs of [AuthBloc]. The router listens to this stream to
/// pick between authenticated and unauthenticated route trees.
sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => <Object?>[];
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthLoading extends AuthState {
  const AuthLoading();
}

final class Authenticated extends AuthState {
  const Authenticated({required this.user});

  final AuthUser user;

  @override
  List<Object?> get props => <Object?>[user];
}

final class Unauthenticated extends AuthState {
  const Unauthenticated();
}
