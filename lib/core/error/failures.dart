import 'package:equatable/equatable.dart';

/// Base class for domain failures.
///
/// Repositories and use cases must return [Failure] inside a `Left` rather
/// than throw. Presentation maps [Failure] subtypes to localized messages.
sealed class Failure extends Equatable {
  const Failure({required this.message, this.code});

  /// User-facing message (already localized by the caller when possible).
  final String message;

  /// Optional machine-readable code for analytics / branching.
  final String? code;

  @override
  List<Object?> get props => <Object?>[message, code];
}

/// Generic remote API failure (non-Supabase HTTP, unexpected status, etc.).
final class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code});
}

/// Local persistence (Drift / file cache) failure.
final class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code});
}

/// OCR pipeline failure (ML Kit / Gemini fallback).
final class OCRFailure extends Failure {
  const OCRFailure({required super.message, super.code});
}

/// Authentication / session failure (Supabase Auth, OAuth providers).
final class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code});
}

/// Connectivity failure — used when the device is offline and the operation
/// requires network access.
final class NetworkFailure extends Failure {
  const NetworkFailure({required super.message, super.code});
}

/// Supabase-specific failure (PostgrestException, StorageException, etc.).
///
/// Kept distinct from [ServerFailure] so we can show "service unavailable"
/// banners and route to offline mode automatically.
final class SupabaseFailure extends Failure {
  const SupabaseFailure({required super.message, super.code});
}

/// Drift ⇄ Supabase sync failure (conflict, queue drain error).
final class SyncFailure extends Failure {
  const SyncFailure({required super.message, super.code});
}

/// Rate limit exceeded — typically from the Gemini OCR Edge Function.
final class RateLimitFailure extends Failure {
  const RateLimitFailure({
    required super.message,
    super.code,
    this.retryAfter,
  });

  /// Optional hint for when the bucket will refill.
  final Duration? retryAfter;

  @override
  List<Object?> get props => <Object?>[...super.props, retryAfter];
}

/// OS-level permission denial (camera, photos, notifications).
final class PermissionFailure extends Failure {
  const PermissionFailure({required super.message, super.code});
}

/// Catch-all for programmer error in domain logic.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({required super.message, super.code});
}
