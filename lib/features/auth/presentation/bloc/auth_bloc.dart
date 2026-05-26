import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/features/auth/domain/entities/auth_user.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Tracks the user's session.
///
/// **Sprint 1 stub:** the bloc fakes an authenticated state so the rest of
/// the navigation graph can be wired up without a real Supabase session.
/// Sprint 8 replaces the [AuthStarted] handler with the real session
/// resolver and subscribes to `supabase.auth.onAuthStateChange`.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(const AuthInitial()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignedOutRequested>(_onSignedOut);
    on<AuthSessionChanged>(_onSessionChanged);
  }

  /// Hardcoded portfolio dev user — only used until Sprint 8.
  static const AuthUser _devUser = AuthUser(
    id: '00000000-0000-0000-0000-000000000000',
    email: 'dev@smartspend.local',
    displayName: 'SmartSpend Dev',
  );

  Future<void> _onStarted(
    AuthStarted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    // TODO(sprint-8): resolve current Supabase session here.
    emit(const Authenticated(user: _devUser));
  }

  Future<void> _onSignedOut(
    AuthSignedOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    // TODO(sprint-8): call supabase.auth.signOut() and clear local caches.
    emit(const Unauthenticated());
  }

  void _onSessionChanged(
    AuthSessionChanged event,
    Emitter<AuthState> emit,
  ) {
    final AuthUser? user = event.user;
    if (user == null) {
      emit(const Unauthenticated());
    } else {
      emit(Authenticated(user: user));
    }
  }
}
