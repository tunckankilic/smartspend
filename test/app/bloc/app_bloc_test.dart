import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/app/bloc/app_bloc.dart';

void main() {
  group('AppBloc', () {
    test('initial state is system theme and null locale', () {
      final AppBloc bloc = AppBloc();
      expect(bloc.state.themeMode, ThemeMode.system);
      expect(bloc.state.locale, isNull);
      bloc.close();
    });

    blocTest<AppBloc, AppState>(
      'should emit dark theme when AppThemeModeChanged is added',
      build: AppBloc.new,
      act: (AppBloc bloc) =>
          bloc.add(const AppThemeModeChanged(ThemeMode.dark)),
      expect: () => <AppState>[
        const AppState(themeMode: ThemeMode.dark, locale: null),
      ],
    );

    blocTest<AppBloc, AppState>(
      'should emit Turkish locale when AppLocaleChanged is added',
      build: AppBloc.new,
      act: (AppBloc bloc) => bloc.add(const AppLocaleChanged(Locale('tr'))),
      expect: () => <AppState>[
        const AppState(themeMode: ThemeMode.system, locale: Locale('tr')),
      ],
    );

    blocTest<AppBloc, AppState>(
      'should clear locale when AppLocaleChanged(null) is added',
      build: AppBloc.new,
      seed: () =>
          const AppState(themeMode: ThemeMode.light, locale: Locale('de')),
      act: (AppBloc bloc) => bloc.add(const AppLocaleChanged(null)),
      expect: () => <AppState>[
        const AppState(themeMode: ThemeMode.light, locale: null),
      ],
    );
  });
}
