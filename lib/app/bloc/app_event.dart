part of 'app_bloc.dart';

sealed class AppEvent extends Equatable {
  const AppEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Toggle between light / dark / system.
final class AppThemeModeChanged extends AppEvent {
  const AppThemeModeChanged(this.mode);

  final ThemeMode mode;

  @override
  List<Object?> get props => <Object?>[mode];
}

/// Pick one of the supported locales. Pass `null` to follow the system.
final class AppLocaleChanged extends AppEvent {
  const AppLocaleChanged(this.locale);

  final Locale? locale;

  @override
  List<Object?> get props => <Object?>[locale];
}
