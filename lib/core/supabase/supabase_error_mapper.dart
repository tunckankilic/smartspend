import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/failures.dart';

/// Translates Supabase SDK exceptions into domain [Failure]s.
///
/// Use this in every datasource that calls Supabase so the rest of the app
/// only sees [Failure]s, never SDK internals.
abstract class SupabaseErrorMapper {
  SupabaseErrorMapper._();

  /// Map any thrown object to a [Failure]. Unknown errors collapse to
  /// [UnexpectedFailure] — callers may still log the original [stackTrace]
  /// to Sentry.
  static Failure map(Object error, [StackTrace? stackTrace]) {
    if (error is PostgrestException) {
      // Postgres / PostgREST — RLS denials surface as 401/403, rate limits 429.
      if (error.code == '429') {
        return RateLimitFailure(
          message: error.message,
          code: error.code,
        );
      }
      return SupabaseFailure(
        message: error.message,
        code: error.code,
      );
    }

    if (error is AuthException) {
      return AuthFailure(
        message: error.message,
        code: error.statusCode,
      );
    }

    if (error is StorageException) {
      return SupabaseFailure(
        message: error.message,
        code: error.statusCode,
      );
    }

    if (error is FunctionException) {
      // Edge Function errors carry a status + details payload.
      final int status = error.status;
      if (status == 429) {
        return RateLimitFailure(
          message: error.reasonPhrase ?? 'Rate limit exceeded',
          code: status.toString(),
        );
      }
      return SupabaseFailure(
        message: error.reasonPhrase ?? 'Edge function failed',
        code: status.toString(),
      );
    }

    return UnexpectedFailure(
      message: error.toString(),
    );
  }
}
