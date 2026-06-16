part of 'settings_cubit.dart';

enum SettingsStatus { initial, loading, ready, failure }

/// Holds the current preferences plus the load/save status. Optimistic
/// updates mutate [preferences] immediately and roll back on failure.
class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.initial,
    this.preferences = UserPreferences.defaults,
    this.failure,
  });

  final SettingsStatus status;
  final UserPreferences preferences;
  final Failure? failure;

  SettingsState copyWith({
    SettingsStatus? status,
    UserPreferences? preferences,
    Failure? failure,
  }) {
    return SettingsState(
      status: status ?? this.status,
      preferences: preferences ?? this.preferences,
      failure: failure,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, preferences, failure];
}
