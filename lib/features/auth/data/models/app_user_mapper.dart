import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/features/auth/domain/entities/app_user.dart';

/// Maps the Supabase SDK [User] onto the domain [AppUser], keeping SDK types
/// out of the domain and presentation layers.
extension SupabaseUserMapper on User {
  AppUser toAppUser() {
    final Map<String, dynamic> metadata = userMetadata ?? <String, dynamic>{};
    final Object? name = metadata['full_name'] ?? metadata['name'];
    final Object? avatar = metadata['avatar_url'] ?? metadata['picture'];
    return AppUser(
      id: id,
      email: email ?? '',
      displayName: name is String && name.isNotEmpty ? name : null,
      avatarUrl: avatar is String && avatar.isNotEmpty ? avatar : null,
      createdAt: DateTime.tryParse(createdAt)?.toUtc(),
    );
  }
}
