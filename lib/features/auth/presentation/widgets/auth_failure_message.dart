import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/data/repositories/supabase_auth_repository_impl.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Maps an [AuthFailure.code] onto a localized, user-facing message. The
/// repository only emits machine-readable codes; localization lives here so
/// the data layer stays free of `BuildContext`.
String authFailureMessage(AppLocalizations l, Failure failure) {
  switch (failure.code) {
    case AuthFailureCode.invalidCredentials:
      return l.authInvalidCredentials;
    case AuthFailureCode.emailNotConfirmed:
      return l.authEmailNotConfirmed;
    case AuthFailureCode.userExists:
      return l.authGenericError;
    case AuthFailureCode.weakPassword:
      return l.authPasswordWeak;
    case AuthFailureCode.network:
      return l.authNetworkError;
    case AuthFailureCode.cancelled:
      return l.authGenericError;
    default:
      return l.authGenericError;
  }
}
