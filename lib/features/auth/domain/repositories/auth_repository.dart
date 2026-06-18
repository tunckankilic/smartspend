import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';

/// Authentication boundary for the domain layer.
///
/// Every fallible action returns `Either<AuthFailure, T>` — the data layer
/// maps Supabase `AuthException`/`PostgrestException` onto [AuthFailure] so
/// the presentation layer never sees SDK types. The session stream is the
/// single source of truth the [AuthBloc] subscribes to.
abstract class AuthRepository {
  /// Emits the current [AppUser] on sign-in and `null` on sign-out.
  Stream<AppUser?> authStateChanges();

  /// The session restored by `supabase_flutter` on cold start, if any.
  AppUser? currentUser();

  Future<Either<AuthFailure, AppUser>> signIn({
    required String email,
    required String password,
  });

  Future<Either<AuthFailure, AppUser>> signUp({
    required String email,
    required String password,
  });

  Future<Either<AuthFailure, AppUser>> signInWithApple();

  Future<Either<AuthFailure, Unit>> signOut();

  Future<Either<AuthFailure, Unit>> resetPassword(String email);

  /// Irreversibly deletes the caller's account server-side (storage objects +
  /// `auth.users` row, which cascades to all owned tables) and ends the local
  /// session. Local Drift cache clearing is the [AuthBloc]'s job once this
  /// resolves, mirroring [signOut].
  Future<Either<AuthFailure, Unit>> deleteAccount();
}
