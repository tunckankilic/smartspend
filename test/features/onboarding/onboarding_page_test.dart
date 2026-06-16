import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

void main() {
  Widget wrap({
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      home: const OnboardingPage(),
    );
  }

  group('OnboardingPage', () {
    testWidgets('renders the headline icon, title and continue button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.savings_rounded), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      for (final Locale locale in const <Locale>[
        Locale('tr'),
        Locale('en'),
        Locale('de'),
      ]) {
        for (final ThemeMode mode in const <ThemeMode>[
          ThemeMode.light,
          ThemeMode.dark,
        ]) {
          await tester.pumpWidget(wrap(locale: locale, themeMode: mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
