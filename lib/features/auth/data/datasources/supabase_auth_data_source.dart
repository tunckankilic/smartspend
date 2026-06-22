// ignore_for_file: prefer_initializing_formals — private field convention.
// coverage:ignore-file
// Thin wrapper over Supabase GoTrue client; mocked at the repository layer.

import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/constants/supabase_constants.dart';
import 'package:smartspend/features/auth/data/models/app_user_mapper.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';

/// Thin wrapper over `supabase_flutter`'s [GoTrueClient] plus the native
/// Sign in with Apple SDK. Throws [AuthException] (and provider exceptions) on
/// failure — the repository is responsible for mapping those onto
/// `AuthFailure`. Nothing above the data layer ever sees an SDK type.
abstract class SupabaseAuthDataSource {
  Stream<AppUser?> authStateChanges();

  AppUser? currentUser();

  Future<AppUser> signInWithPassword({
    required String email,
    required String password,
  });

  Future<AppUser> signUp({
    required String email,
    required String password,
  });

  Future<AppUser> signInWithApple();

  Future<void> signOut();

  Future<void> resetPassword(String email);

  Future<void> deleteAccount();
}

class SupabaseAuthDataSourceImpl implements SupabaseAuthDataSource {
  SupabaseAuthDataSourceImpl({
    required GoTrueClient auth,
    required FunctionsClient functions,
  })  : _auth = auth,
        _functions = functions;

  final GoTrueClient _auth;
  final FunctionsClient _functions;

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.onAuthStateChange.map(
      (AuthState data) => data.session?.user.toAppUser(),
    );
  }

  @override
  AppUser? currentUser() => _auth.currentUser?.toAppUser();

  @override
  Future<AppUser> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _requireUser(response);
  }

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: SupabaseConstants.oauthRedirectUrl,
    );
    // With email confirmation enabled the session is null but the user row
    // exists — that is still a successful sign-up; the bloc decides whether
    // to route to the confirmation screen.
    final User? user = response.user;
    if (user == null) {
      throw const AuthException('Kayıt tamamlanamadı.');
    }
    return user.toAppUser();
  }

  @override
  Future<AppUser> signInWithApple() async {
    final AuthorizationCredentialAppleID credential =
        await SignInWithApple.getAppleIDCredential(
      scopes: <AppleIDAuthorizationScopes>[
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final String? idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple kimlik jetonu alınamadı.');
    }
    final AuthResponse response = await _auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
    );
    // Apple only returns the user's name on the FIRST authorization, and only
    // via the native credential — never in the id_token. Capture it here and
    // persist to user_metadata so the mapper can read `full_name` on every
    // later sign-in. Skipped (and never clobbered) when Apple omits the name.
    final String fullName = <String?>[
      credential.givenName,
      credential.familyName,
    ].whereType<String>().where((String s) => s.isNotEmpty).join(' ');
    if (fullName.isNotEmpty) {
      final UserResponse updated = await _auth.updateUser(
        UserAttributes(data: <String, dynamic>{'full_name': fullName}),
      );
      final User? user = updated.user;
      if (user != null) {
        return user.toAppUser();
      }
    }
    return _requireUser(response);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> resetPassword(String email) {
    return _auth.resetPasswordForEmail(
      email,
      redirectTo: SupabaseConstants.oauthRedirectUrl,
    );
  }

  @override
  Future<void> deleteAccount() async {
    // The Edge Function authenticates via the caller's JWT (attached
    // automatically by the SDK), purges storage + the auth row, then cascades
    // to every owned table. `invoke` throws FunctionException on a non-2xx
    // response — the repository maps that onto AuthFailure.
    await _functions.invoke(
      SupabaseConstants.fnDeleteAccount,
      body: <String, String>{
        'confirm': SupabaseConstants.deleteAccountConfirmToken,
      },
    );
    // The server already deleted the user; sign out locally to drop the now
    // orphaned session and tokens.
    await _auth.signOut();
  }

  AppUser _requireUser(AuthResponse response) {
    final User? user = response.user;
    if (user == null) {
      throw const AuthException('Oturum açılamadı.');
    }
    return user.toAppUser();
  }
}
