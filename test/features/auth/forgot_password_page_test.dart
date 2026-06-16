import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart' as failures;
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

void main() {
  late _MockAuthBloc bloc;

  setUpAll(() {
    registerFallbackValue(const AuthPasswordResetRequested(email: 'x@x.com'));
  });

  setUp(() {
    bloc = _MockAuthBloc();
  });

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
      home: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: const ForgotPasswordPage(),
      ),
    );
  }

  group('ForgotPasswordPage', () {
    testWidgets('renders the email field and submit button', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const Unauthenticated());
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows a spinner inside the button while loading', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const AuthLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the reset-sent confirmation after a successful reset', (
      WidgetTester tester,
    ) async {
      final StreamController<AuthState> controller =
          StreamController<AuthState>();
      whenListen(
        bloc,
        controller.stream,
        initialState: const Unauthenticated(),
      );
      addTearDown(controller.close);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'jane@example.com');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      controller.add(const Unauthenticated());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
      verify(
        () => bloc.add(
          const AuthPasswordResetRequested(email: 'jane@example.com'),
        ),
      ).called(1);
    });

    testWidgets('shows a snackbar on failure and stays on the form', (
      WidgetTester tester,
    ) async {
      final StreamController<AuthState> controller =
          StreamController<AuthState>();
      whenListen(
        bloc,
        controller.stream,
        initialState: const Unauthenticated(),
      );
      addTearDown(controller.close);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'jane@example.com');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      controller.add(
        const AuthFailure(failures.ServerFailure(message: 'nope')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const Unauthenticated());

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
