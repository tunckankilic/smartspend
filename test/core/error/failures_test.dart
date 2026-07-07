import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';

/// Equality contracts for the [Failure] / [AppException] hierarchies —
/// repositories branch on these types, and blocs dedupe re-emitted
/// failure states via Equatable.
void main() {
  group('Failure equality', () {
    test('should compare by message and code within a subtype', () {
      expect(
        const NetworkFailure(message: 'offline', code: 'net'),
        const NetworkFailure(message: 'offline', code: 'net'),
      );
      expect(
        const SyncFailure(message: 'conflict'),
        isNot(const SyncFailure(message: 'queue full')),
      );
    });

    test('should include retryAfter in RateLimitFailure equality', () {
      expect(
        const RateLimitFailure(
          message: 'limit',
          retryAfter: Duration(hours: 1),
        ),
        const RateLimitFailure(
          message: 'limit',
          retryAfter: Duration(hours: 1),
        ),
      );
      expect(
        const RateLimitFailure(
          message: 'limit',
          retryAfter: Duration(hours: 1),
        ),
        isNot(const RateLimitFailure(message: 'limit')),
      );
    });
  });

  group('AppException subtypes', () {
    test('should carry message and code through the constructor', () {
      const AuthException auth = AuthException(message: 'bad', code: 'a1');
      expect(auth.message, 'bad');
      expect(auth.code, 'a1');

      const NetworkException net = NetworkException(message: 'offline');
      expect(net.code, isNull);

      const SupabaseException supa = SupabaseException(message: '503');
      expect(supa.message, '503');

      const SyncException sync = SyncException(message: 'conflict');
      expect(sync.message, 'conflict');
    });
  });
}
