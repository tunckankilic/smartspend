import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

part 'app_event.dart';
part 'app_state.dart';

/// Global preferences shared by the whole UI shell — currently just theme
/// and locale. Persistence (writing back to Drift's `UserSettings`) lands
/// in Sprint 8 alongside cloud-synced preferences.
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(const AppState.initial()) {
    on<AppThemeModeChanged>(
      (AppThemeModeChanged event, Emitter<AppState> emit) =>
          emit(state.copyWith(themeMode: event.mode)),
    );
    on<AppLocaleChanged>(
      (AppLocaleChanged event, Emitter<AppState> emit) => emit(
        event.locale == null
            ? state.copyWith(clearLocale: true)
            : state.copyWith(locale: event.locale),
      ),
    );
  }
}
