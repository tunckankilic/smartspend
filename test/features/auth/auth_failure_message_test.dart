import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/error/failure_codes.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/presentation/widgets/auth_failure_message.dart';
import 'package:smartspend/l10n/generated/app_localizations_en.dart';

/// Pins the [AuthFailureCode] → localized string mapping.
void main() {
  final AppLocalizationsEn l = AppLocalizationsEn();

  AuthFailure failure(String code) => AuthFailure(message: 'raw', code: code);

  group('authFailureMessage', () {
    test('should map every known code to its localized message', () {
      expect(
        authFailureMessage(l, failure(AuthFailureCode.invalidCredentials)),
        l.authInvalidCredentials,
      );
      expect(
        authFailureMessage(l, failure(AuthFailureCode.emailNotConfirmed)),
        l.authEmailNotConfirmed,
      );
      expect(
        authFailureMessage(l, failure(AuthFailureCode.userExists)),
        l.authGenericError,
      );
      expect(
        authFailureMessage(l, failure(AuthFailureCode.weakPassword)),
        l.authPasswordWeak,
      );
      expect(
        authFailureMessage(l, failure(AuthFailureCode.network)),
        l.authNetworkError,
      );
      expect(
        authFailureMessage(l, failure(AuthFailureCode.cancelled)),
        l.authGenericError,
      );
    });

    test('should fall back to the generic message for unknown codes', () {
      expect(
        authFailureMessage(l, failure('something-new')),
        l.authGenericError,
      );
      expect(
        authFailureMessage(l, const AuthFailure(message: 'raw')),
        l.authGenericError,
      );
    });
  });
}
