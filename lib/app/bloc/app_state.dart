part of 'app_bloc.dart';

class AppState extends Equatable {
  const AppState({
    required this.themeMode,
    required this.locale,
  });

  const AppState.initial()
      : themeMode = ThemeMode.system,
        locale = null;

  final ThemeMode themeMode;

  /// `null` means follow the device locale.
  final Locale? locale;

  AppState copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool clearLocale = false,
  }) {
    return AppState(
      themeMode: themeMode ?? this.themeMode,
      locale: clearLocale ? null : (locale ?? this.locale),
    );
  }

  @override
  List<Object?> get props => <Object?>[themeMode, locale];
}
