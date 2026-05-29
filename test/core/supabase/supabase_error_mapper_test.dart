import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/supabase/supabase_error_mapper.dart';

void main() {
  group('SupabaseErrorMapper.map', () {
    test('should map a PostgrestException to SupabaseFailure', () {
      final Failure f = SupabaseErrorMapper.map(
        const PostgrestException(message: 'denied', code: '403'),
      );
      expect(f, isA<SupabaseFailure>());
      expect(f.message, 'denied');
      expect(f.code, '403');
    });

    test('should map a 429 PostgrestException to RateLimitFailure', () {
      final Failure f = SupabaseErrorMapper.map(
        const PostgrestException(message: 'slow down', code: '429'),
      );
      expect(f, isA<RateLimitFailure>());
      expect(f.code, '429');
    });

    test('should map an AuthException to AuthFailure', () {
      final Failure f = SupabaseErrorMapper.map(
        const AuthException('bad creds', statusCode: '401'),
      );
      expect(f, isA<AuthFailure>());
      expect(f.message, 'bad creds');
      expect(f.code, '401');
    });

    test('should map a StorageException to SupabaseFailure', () {
      final Failure f = SupabaseErrorMapper.map(
        const StorageException('missing object', statusCode: '404'),
      );
      expect(f, isA<SupabaseFailure>());
      expect(f.code, '404');
    });

    test('should map a 429 FunctionException to RateLimitFailure', () {
      final Failure f = SupabaseErrorMapper.map(
        const FunctionException(status: 429, reasonPhrase: 'too many'),
      );
      expect(f, isA<RateLimitFailure>());
      expect(f.message, 'too many');
      expect(f.code, '429');
    });

    test('should map a non-429 FunctionException to SupabaseFailure', () {
      final Failure f = SupabaseErrorMapper.map(
        const FunctionException(status: 500, reasonPhrase: 'boom'),
      );
      expect(f, isA<SupabaseFailure>());
      expect(f.code, '500');
    });

    test('should fall back to a default reason when FunctionException has none',
        () {
      final Failure f = SupabaseErrorMapper.map(
        const FunctionException(status: 500),
      );
      expect(f, isA<SupabaseFailure>());
      expect(f.message, 'Edge function failed');
    });

    test('should map an unknown error to UnexpectedFailure', () {
      final Failure f = SupabaseErrorMapper.map(Exception('weird'));
      expect(f, isA<UnexpectedFailure>());
      expect(f.message, contains('weird'));
    });
  });
}
