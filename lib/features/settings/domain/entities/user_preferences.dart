import 'package:equatable/equatable.dart';

import 'package:smartspend/core/constants/app_constants.dart';

/// Cloud-synced user preferences surfaced on the Settings page.
///
/// Theme and locale live in [AppBloc] (device-local), so they are not part
/// of this entity. Currency and notification opt-in are persisted to the
/// `user_settings` table.
class UserPreferences extends Equatable {
  const UserPreferences({
    required this.currencyCode,
    required this.notificationsEnabled,
  });

  /// Sensible defaults for a fresh install before anything is stored.
  static const UserPreferences defaults = UserPreferences(
    currencyCode: AppConstants.defaultCurrency,
    notificationsEnabled: true,
  );

  /// ISO-4217 code; one of `kSupportedCurrencies`.
  final String currencyCode;

  /// Whether budget alerts and reminders are enabled.
  final bool notificationsEnabled;

  UserPreferences copyWith({
    String? currencyCode,
    bool? notificationsEnabled,
  }) {
    return UserPreferences(
      currencyCode: currencyCode ?? this.currencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  @override
  List<Object?> get props => <Object?>[currencyCode, notificationsEnabled];
}
