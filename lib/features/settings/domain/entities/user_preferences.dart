import 'package:equatable/equatable.dart';

import 'package:smartspend/core/constants/app_constants.dart';
import 'package:smartspend/features/settings/domain/entities/ai_consent_status.dart';

/// Cloud-synced user preferences surfaced on the Settings page.
///
/// Theme and locale live in [AppBloc] (device-local), so they are not part
/// of this entity. Currency, notification opt-in, and the AI-scanning
/// consent are persisted to the `user_settings` table.
class UserPreferences extends Equatable {
  const UserPreferences({
    required this.currencyCode,
    required this.notificationsEnabled,
    this.aiConsent = AiConsentStatus.notAsked,
  });

  /// Sensible defaults for a fresh install before anything is stored.
  /// [aiConsent] defaults to [AiConsentStatus.notAsked] — consent is never
  /// assumed; the scan flow must ask before any cloud OCR call.
  static const UserPreferences defaults = UserPreferences(
    currencyCode: AppConstants.defaultCurrency,
    notificationsEnabled: true,
  );

  /// ISO-4217 code; one of `kSupportedCurrencies`.
  final String currencyCode;

  /// Whether budget alerts and reminders are enabled.
  final bool notificationsEnabled;

  /// Whether the user allows sending receipt photos to Google Gemini when
  /// on-device OCR falls short. See [AiConsentStatus].
  final AiConsentStatus aiConsent;

  UserPreferences copyWith({
    String? currencyCode,
    bool? notificationsEnabled,
    AiConsentStatus? aiConsent,
  }) {
    return UserPreferences(
      currencyCode: currencyCode ?? this.currencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      aiConsent: aiConsent ?? this.aiConsent,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    currencyCode,
    notificationsEnabled,
    aiConsent,
  ];
}
