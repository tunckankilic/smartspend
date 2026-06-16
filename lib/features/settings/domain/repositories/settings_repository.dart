import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';

/// Reads and writes cloud-synced user preferences (currency, notifications).
///
/// Backed locally by the `user_settings` Drift table; the sync engine
/// mirrors it to Supabase. Reads fall back to [UserPreferences.defaults]
/// when nothing is stored yet.
abstract class SettingsRepository {
  Future<Either<Failure, UserPreferences>> getPreferences();

  Future<Either<Failure, Unit>> setCurrency(String currencyCode);

  /// A bare on/off flag — a named param would add no clarity here.
  // ignore: avoid_positional_boolean_parameters
  Future<Either<Failure, Unit>> setNotificationsEnabled(bool enabled);
}
