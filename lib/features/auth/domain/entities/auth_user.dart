import 'package:equatable/equatable.dart';

/// Minimal user representation used across the app.
///
/// Backed by `auth.users` in Supabase, but the domain layer stays free of
/// SDK types. Sprint 8 wires the real Supabase user mapping.
class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;

  @override
  List<Object?> get props => <Object?>[id, email, displayName, avatarUrl];
}
