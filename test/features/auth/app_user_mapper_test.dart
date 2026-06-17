import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/features/auth/data/models/app_user_mapper.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';

// ---------------------------------------------------------------------------
// Helper: builds a Supabase User with sensible defaults.
// ---------------------------------------------------------------------------

User _makeUser({
  String id = 'test-uid',
  String? email = 'user@example.com',
  String createdAt = '2026-01-15T10:00:00.000Z',
  Map<String, dynamic>? userMetadata,
  Map<String, dynamic>? appMetadata,
}) {
  return User(
    id: id,
    appMetadata: appMetadata ?? <String, dynamic>{},
    userMetadata: userMetadata,
    aud: 'authenticated',
    createdAt: createdAt,
    email: email,
  );
}

void main() {
  group('SupabaseUserMapper.toAppUser()', () {
    group('happy path', () {
      test('should map id and email correctly', () {
        final User user = _makeUser(
          id: 'uid-123',
          email: 'alice@example.com',
          userMetadata: <String, dynamic>{'full_name': 'Alice'},
        );

        final AppUser result = user.toAppUser();

        expect(result.id, 'uid-123');
        expect(result.email, 'alice@example.com');
      });

      test('should map displayName from "full_name" metadata key', () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{'full_name': 'Alice Doe'},
        );

        expect(user.toAppUser().displayName, 'Alice Doe');
      });

      test('should map displayName from "name" when "full_name" is absent', () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{'name': 'Bob'},
        );

        expect(user.toAppUser().displayName, 'Bob');
      });

      test('should prefer "full_name" over "name" when both are present', () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{
            'full_name': 'Charlie Full',
            'name': 'Charlie Short',
          },
        );

        expect(user.toAppUser().displayName, 'Charlie Full');
      });

      test('should map avatarUrl from "avatar_url" metadata key', () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{
            'avatar_url': 'https://cdn.example.com/avatar.jpg',
          },
        );

        expect(
          user.toAppUser().avatarUrl,
          'https://cdn.example.com/avatar.jpg',
        );
      });

      test('should map avatarUrl from "picture" when "avatar_url" is absent',
          () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{
            'picture': 'https://lh3.googleusercontent.com/photo.jpg',
          },
        );

        expect(
          user.toAppUser().avatarUrl,
          'https://lh3.googleusercontent.com/photo.jpg',
        );
      });

      test('should prefer "avatar_url" over "picture" when both are present',
          () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{
            'avatar_url': 'https://storage.example.com/a.jpg',
            'picture': 'https://google.com/pic.jpg',
          },
        );

        expect(
          user.toAppUser().avatarUrl,
          'https://storage.example.com/a.jpg',
        );
      });

      test('should parse createdAt as UTC DateTime', () {
        final User user = _makeUser(
          createdAt: '2026-01-15T10:00:00.000Z',
        );

        expect(
          user.toAppUser().createdAt,
          DateTime.utc(2026, 1, 15, 10, 0, 0),
        );
      });
    });

    group('null / missing fields', () {
      test('should fall back to empty string when email is null', () {
        final User user = _makeUser(email: null);

        expect(user.toAppUser().email, '');
      });

      test('should produce null displayName when userMetadata is null', () {
        final User user = _makeUser(userMetadata: null);

        expect(user.toAppUser().displayName, isNull);
      });

      test('should produce null avatarUrl when userMetadata is null', () {
        final User user = _makeUser(userMetadata: null);

        expect(user.toAppUser().avatarUrl, isNull);
      });

      test('should produce null displayName when both name keys are absent',
          () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{'other_key': 'value'},
        );

        expect(user.toAppUser().displayName, isNull);
      });

      test('should produce null displayName when full_name is an empty string',
          () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{'full_name': ''},
        );

        expect(user.toAppUser().displayName, isNull);
      });

      test('should produce null avatarUrl when avatar_url is an empty string',
          () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{'avatar_url': ''},
        );

        expect(user.toAppUser().avatarUrl, isNull);
      });

      test('should produce null createdAt when createdAt string is invalid',
          () {
        final User user = _makeUser(createdAt: 'not-a-date');

        expect(user.toAppUser().createdAt, isNull);
      });

      test('should produce null displayName when full_name value is not String',
          () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{'full_name': 42},
        );

        expect(user.toAppUser().displayName, isNull);
      });

      test('should produce null avatarUrl when avatar_url value is not String',
          () {
        final User user = _makeUser(
          userMetadata: <String, dynamic>{'avatar_url': true},
        );

        expect(user.toAppUser().avatarUrl, isNull);
      });
    });

    group('Equatable', () {
      test('should produce equal AppUsers from equivalent User objects', () {
        final User u1 = _makeUser(
          userMetadata: <String, dynamic>{'full_name': 'Alice'},
        );
        final User u2 = _makeUser(
          userMetadata: <String, dynamic>{'full_name': 'Alice'},
        );

        expect(u1.toAppUser(), u2.toAppUser());
      });

      test('should produce distinct AppUsers when names differ', () {
        final User u1 = _makeUser(
          id: 'uid-1',
          userMetadata: <String, dynamic>{'full_name': 'Alice'},
        );
        final User u2 = _makeUser(
          id: 'uid-2',
          userMetadata: <String, dynamic>{'full_name': 'Bob'},
        );

        expect(u1.toAppUser(), isNot(u2.toAppUser()));
      });
    });
  });
}
