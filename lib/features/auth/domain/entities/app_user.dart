import 'package:equatable/equatable.dart';

/// Minimal user representation used across the app.
///
/// Backed by `auth.users` in Supabase, but the domain layer stays free of
/// SDK types — the data layer maps the Supabase `User` onto this entity.
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.createdAt,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? createdAt;

  @override
  List<Object?> get props =>
      <Object?>[id, email, displayName, avatarUrl, createdAt];
}
