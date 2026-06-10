/// Machine-readable `Failure.code` values shared across layers.
///
/// Data sources emit these, repositories attach them to `Failure`s, and
/// the presentation layer maps them onto localized strings. They live in
/// `core/error` (not in a data source or repository file) so presentation
/// can branch on a code without importing the data layer.
library;

/// Codes attached to `AuthFailure`. The human-readable `message` field is
/// for logging only — never show it to the user.
abstract class AuthFailureCode {
  AuthFailureCode._();

  static const String invalidCredentials = 'invalid_credentials';
  static const String emailNotConfirmed = 'email_not_confirmed';
  static const String userExists = 'user_already_exists';
  static const String weakPassword = 'weak_password';
  static const String network = 'network';
  static const String cancelled = 'cancelled';
  static const String unknown = 'unknown';
}

/// Sentinel code emitted when the user backs out of the system camera /
/// gallery picker. The scan flow translates this into a silent
/// return-to-initial rather than a surfaced error.
const String kCameraCancelledCode = 'cancelled';
