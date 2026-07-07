import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/app/bloc/app_bloc.dart';

/// Equality contracts for [AppEvent] subtypes.
void main() {
  group('AppEvent equality', () {
    test('should compare AppThemeModeChanged by mode', () {
      expect(
        const AppThemeModeChanged(ThemeMode.dark),
        const AppThemeModeChanged(ThemeMode.dark),
      );
      expect(
        const AppThemeModeChanged(ThemeMode.dark),
        isNot(const AppThemeModeChanged(ThemeMode.light)),
      );
    });

    test('should compare AppLocaleChanged by locale (null = system)', () {
      expect(
        const AppLocaleChanged(Locale('tr')),
        const AppLocaleChanged(Locale('tr')),
      );
      expect(
        const AppLocaleChanged(Locale('tr')),
        isNot(const AppLocaleChanged(null)),
      );
    });
  });
}
