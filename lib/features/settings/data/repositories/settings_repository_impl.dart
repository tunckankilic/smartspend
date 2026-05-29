import 'package:dartz/dartz.dart';

import 'package:smartspend/core/constants/app_constants.dart';
import 'package:smartspend/core/database/daos/user_settings_dao.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';

/// Drift-backed [SettingsRepository].
///
/// Stores each preference as a key/value row in `user_settings`. Unknown or
/// unset keys resolve to [UserPreferences.defaults]; an invalid stored
/// currency falls back to the app default so a corrupt write never breaks
/// formatting.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({required this.dao});

  final UserSettingsDao dao;

  static const String _kCurrency = 'default_currency';
  static const String _kNotifications = 'notifications_enabled';

  @override
  Future<Either<Failure, UserPreferences>> getPreferences() async {
    try {
      final String? currency = await dao.getValue(_kCurrency);
      final String? notifications = await dao.getValue(_kNotifications);
      final String resolvedCurrency =
          (currency != null && kSupportedCurrencies.contains(currency))
              ? currency
              : AppConstants.defaultCurrency;
      return Right<Failure, UserPreferences>(
        UserPreferences(
          currencyCode: resolvedCurrency,
          notificationsEnabled: notifications == null
              ? UserPreferences.defaults.notificationsEnabled
              : notifications == 'true',
        ),
      );
    } on Object catch (e) {
      return Left<Failure, UserPreferences>(
        CacheFailure(message: e.toString()),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> setCurrency(String currencyCode) async {
    if (!kSupportedCurrencies.contains(currencyCode)) {
      return const Left<Failure, Unit>(
        CacheFailure(message: 'Unsupported currency'),
      );
    }
    return _write(_kCurrency, currencyCode);
  }

  @override
  Future<Either<Failure, Unit>> setNotificationsEnabled(bool enabled) {
    return _write(_kNotifications, enabled ? 'true' : 'false');
  }

  Future<Either<Failure, Unit>> _write(String key, String value) async {
    try {
      await dao.setValue(key, value);
      return const Right<Failure, Unit>(unit);
    } on Object catch (e) {
      return Left<Failure, Unit>(CacheFailure(message: e.toString()));
    }
  }
}
