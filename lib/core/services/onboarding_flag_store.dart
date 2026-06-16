import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the user has finished the first-launch onboarding flow.
///
/// Backed by `SharedPreferences` so the value survives reinstalls only on
/// Android (per platform behaviour). On a fresh install the user is sent to
/// `/onboarding` once.
class OnboardingFlagStore {
  OnboardingFlagStore(this._prefs);

  static const String _kCompleteKey = 'onboarding.complete';

  final SharedPreferences _prefs;

  bool get isComplete => _prefs.getBool(_kCompleteKey) ?? false;

  Future<void> markComplete() => _prefs.setBool(_kCompleteKey, true);

  Future<void> reset() => _prefs.remove(_kCompleteKey);
}
