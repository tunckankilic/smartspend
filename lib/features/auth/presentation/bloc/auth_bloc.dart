// ignore_for_file: prefer_initializing_formals — private field convention.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart' show Failure;
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/domain/repositories/auth_repository.dart';
import 'package:smartspend/features/auth/domain/usecases/apple_sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/delete_account_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/reset_password_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_in_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:smartspend/features/auth/domain/usecases/sign_up_usecase.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Owns the user's session.
///
/// Subscribes to [AuthRepository.authStateChanges] for the duration of its
/// life and folds every use-case result into one of the five [AuthState]s.
/// User-triggered mutations run [sequential] (only one auth action at a
/// time); the session stream tick runs [restartable] so a newer session
/// always wins over an in-flight resolve.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthRepository authRepository,
    required SignInUseCase signIn,
    required SignUpUseCase signUp,
    required SignOutUseCase signOut,
    required DeleteAccountUseCase deleteAccount,
    required AppleSignInUseCase appleSignIn,
    required ResetPasswordUseCase resetPassword,
    required AppDatabase database,
    required SyncService syncService,
  })  : _authRepository = authRepository,
        _signIn = signIn,
        _signUp = signUp,
        _signOut = signOut,
        _deleteAccount = deleteAccount,
        _appleSignIn = appleSignIn,
        _resetPassword = resetPassword,
        _database = database,
        _syncService = syncService,
        super(const AuthInitial()) {
    on<AuthCheckRequested>(_onResolve);
    on<AuthSessionRestored>(_onResolve);
    on<AuthSignInRequested>(_onSignIn, transformer: sequential());
    on<AuthSignUpRequested>(_onSignUp, transformer: sequential());
    on<AuthSignOutRequested>(_onSignOut, transformer: sequential());
    on<AuthSignOutConfirmed>(_onSignOutConfirmed, transformer: sequential());
    on<AuthAccountDeletionRequested>(
      _onDeleteAccount,
      transformer: sequential(),
    );
    on<AuthAppleRequested>(_onApple, transformer: sequential());
    on<AuthPasswordResetRequested>(_onReset, transformer: sequential());
    on<AuthStateChanged>(_onStateChanged, transformer: restartable());

    _subscription = _authRepository.authStateChanges().listen(
          (AppUser? user) => add(AuthStateChanged(user: user)),
        );
  }

  final AuthRepository _authRepository;
  final SignInUseCase _signIn;
  final SignUpUseCase _signUp;
  final SignOutUseCase _signOut;
  final DeleteAccountUseCase _deleteAccount;
  final AppleSignInUseCase _appleSignIn;
  final ResetPasswordUseCase _resetPassword;
  final AppDatabase _database;
  final SyncService _syncService;

  late final StreamSubscription<AppUser?> _subscription;

  @override
  void onChange(Change<AuthState> change) {
    super.onChange(change);
    // A session just became active (sign-in, Apple, or a cold-start restore).
    // Kick a full sync so locally-created rows reach the server promptly and
    // remote rows are pulled back, instead of waiting for the periodic timer.
    // The gap between "add data" and the first push is exactly how a fast
    // sign-out used to wipe never-pushed rows.
    if (change.nextState is Authenticated &&
        change.currentState is! Authenticated) {
      unawaited(_syncService.sync());
    }
  }

  void _onResolve(AuthEvent event, Emitter<AuthState> emit) {
    final AppUser? user = _authRepository.currentUser();
    emit(user == null ? const Unauthenticated() : Authenticated(user: user));
  }

  Future<void> _onSignIn(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final Either<Failure, AppUser> result = await _signIn(
      SignInParams(email: event.email, password: event.password),
    );
    emit(
      result.fold(
        AuthFailure.new,
        (AppUser user) => Authenticated(user: user),
      ),
    );
  }

  Future<void> _onSignUp(
    AuthSignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final Either<Failure, AppUser> result = await _signUp(
      SignUpParams(email: event.email, password: event.password),
    );
    emit(
      result.fold(
        AuthFailure.new,
        // With email confirmation enabled the session is still null after
        // sign-up — the UI routes to the "check your inbox" screen.
        (AppUser user) => _authRepository.currentUser() == null
            ? const Unauthenticated()
            : Authenticated(user: user),
      ),
    );
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    // Flush pending writes BEFORE signing out: the session is still alive
    // here, so push can satisfy RLS. Once `_signOut` runs the uid is gone and
    // `clearUserData` wipes the cache, so anything unsynced would be lost. A
    // timeout stops a hung/slow server from freezing sign-out — the queue
    // just stays pending and the user is warned below.
    await _syncService.push().timeout(
      const Duration(seconds: 10),
      onTimeout: () => const Right<Failure, SyncReport>(SyncReport()),
    );
    final int pending = await _syncService.pendingCount();
    if (pending > 0) {
      // Could not drain the queue (offline, or a row the server rejects).
      // Hand off to the UI to confirm discarding before the wipe.
      emit(AuthSignOutPendingConfirmation(pendingCount: pending));
      return;
    }
    await _finishSignOut(emit);
  }

  Future<void> _onSignOutConfirmed(
    AuthSignOutConfirmed event,
    Emitter<AuthState> emit,
  ) async {
    // User accepted losing the still-pending rows; complete the wipe.
    emit(const AuthLoading());
    await _finishSignOut(emit);
  }

  Future<void> _finishSignOut(Emitter<AuthState> emit) async {
    final Either<Failure, Unit> result = await _signOut();
    await result.fold(
      (Failure failure) async => emit(AuthFailure(failure)),
      (_) async {
        await _database.clearUserData();
        emit(const Unauthenticated());
      },
    );
  }

  Future<void> _onDeleteAccount(
    AuthAccountDeletionRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final Either<Failure, Unit> result = await _deleteAccount();
    await result.fold(
      (Failure failure) async => emit(AuthFailure(failure)),
      (_) async {
        await _database.clearUserData();
        emit(const Unauthenticated());
      },
    );
  }

  Future<void> _onApple(
    AuthAppleRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final Either<Failure, AppUser> result = await _appleSignIn();
    emit(
      result.fold(
        AuthFailure.new,
        (AppUser user) => Authenticated(user: user),
      ),
    );
  }

  Future<void> _onReset(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final Either<Failure, Unit> result = await _resetPassword(event.email);
    emit(
      result.fold(
        AuthFailure.new,
        (_) => const Unauthenticated(),
      ),
    );
  }

  void _onStateChanged(AuthStateChanged event, Emitter<AuthState> emit) {
    final AppUser? user = event.user;
    emit(user == null ? const Unauthenticated() : Authenticated(user: user));
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
