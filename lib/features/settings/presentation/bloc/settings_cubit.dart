// ignore_for_file: prefer_initializing_formals — private field convention.
// ignore_for_file: avoid_positional_boolean_parameters — mirrors repository.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/entities/ai_consent_status.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_ai_consent.dart';
import 'package:smartspend/features/settings/domain/usecases/set_currency.dart';
import 'package:smartspend/features/settings/domain/usecases/set_notifications_enabled.dart';

part 'settings_state.dart';

/// Owns the cloud-synced preferences shown on the Settings page (currency,
/// notifications). Theme/locale stay in [AppBloc]; this cubit only touches
/// what persists to `user_settings`.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required GetPreferencesUseCase getPreferences,
    required SetCurrencyUseCase setCurrency,
    required SetNotificationsEnabledUseCase setNotifications,
    required SetAiConsentUseCase setAiConsentUseCase,
  }) : _getPreferences = getPreferences,
       _setCurrency = setCurrency,
       _setNotifications = setNotifications,
       _setAiConsent = setAiConsentUseCase,
       super(const SettingsState());

  final GetPreferencesUseCase _getPreferences;
  final SetCurrencyUseCase _setCurrency;
  final SetNotificationsEnabledUseCase _setNotifications;
  final SetAiConsentUseCase _setAiConsent;

  Future<void> load() async {
    emit(state.copyWith(status: SettingsStatus.loading));
    final Either<Failure, UserPreferences> result = await _getPreferences(
      const NoParams(),
    );
    result.fold(
      (Failure f) => emit(
        state.copyWith(status: SettingsStatus.failure, failure: f),
      ),
      (UserPreferences prefs) => emit(
        state.copyWith(status: SettingsStatus.ready, preferences: prefs),
      ),
    );
  }

  Future<void> changeCurrency(String currencyCode) async {
    final UserPreferences prev = state.preferences;
    emit(
      state.copyWith(
        preferences: prev.copyWith(currencyCode: currencyCode),
      ),
    );
    final Either<Failure, Unit> result = await _setCurrency(currencyCode);
    result.fold(
      (Failure f) => emit(
        state.copyWith(
          status: SettingsStatus.failure,
          failure: f,
          preferences: prev,
        ),
      ),
      (_) {},
    );
  }

  Future<void> toggleNotifications(bool enabled) async {
    final UserPreferences prev = state.preferences;
    emit(
      state.copyWith(
        preferences: prev.copyWith(notificationsEnabled: enabled),
      ),
    );
    final Either<Failure, Unit> result = await _setNotifications(enabled);
    result.fold(
      (Failure f) => emit(
        state.copyWith(
          status: SettingsStatus.failure,
          failure: f,
          preferences: prev,
        ),
      ),
      (_) {},
    );
  }

  /// Grants or revokes the third-party AI (Google Gemini) consent from the
  /// Settings toggle. Optimistic like the other setters; rolls back on a
  /// failed write, which also keeps the scan repository's fail-closed gate
  /// truthful (it re-reads the stored value on every scan).
  Future<void> setAiConsent({required bool granted}) async {
    final UserPreferences prev = state.preferences;
    emit(
      state.copyWith(
        preferences: prev.copyWith(
          aiConsent: granted ? AiConsentStatus.granted : AiConsentStatus.denied,
        ),
      ),
    );
    final Either<Failure, Unit> result = await _setAiConsent(granted);
    result.fold(
      (Failure f) => emit(
        state.copyWith(
          status: SettingsStatus.failure,
          failure: f,
          preferences: prev,
        ),
      ),
      (_) {},
    );
  }
}
