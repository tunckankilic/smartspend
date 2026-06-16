/// Data-layer exceptions.
///
/// Thrown by data sources and caught by repository implementations, which
/// map them to [Failure]s. They never cross the data layer boundary.
sealed class AppException implements Exception {
  const AppException({required this.message, this.code});

  final String message;
  final String? code;

  @override
  String toString() =>
      '$runtimeType(message: $message${code == null ? '' : ', code: $code'})';
}

final class ServerException extends AppException {
  const ServerException({required super.message, super.code});
}

final class CacheException extends AppException {
  const CacheException({required super.message, super.code});
}

final class OCRException extends AppException {
  const OCRException({required super.message, super.code});
}

final class AuthException extends AppException {
  const AuthException({required super.message, super.code});
}

final class NetworkException extends AppException {
  const NetworkException({required super.message, super.code});
}

final class SupabaseException extends AppException {
  const SupabaseException({required super.message, super.code});
}

final class SyncException extends AppException {
  const SyncException({required super.message, super.code});
}

final class RateLimitException extends AppException {
  const RateLimitException({
    required super.message,
    super.code,
    this.retryAfter,
  });

  final Duration? retryAfter;
}

final class PermissionException extends AppException {
  const PermissionException({required super.message, super.code});
}
