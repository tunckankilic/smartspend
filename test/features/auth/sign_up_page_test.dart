import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/pages/sign_up_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

Widget _wrap(AuthBloc bloc) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: BlocProvider<AuthBloc>.value(
      value: bloc,
      child: const SignUpPage(),
    ),
  );
}

void main() {
  late _MockAuthBloc bloc;

  setUpAll(() {
    registerFallbackValue(
      const AuthSignUpRequested(email: 'a@b.com', password: 'x'),
    );
  });

  setUp(() {
    bloc = _MockAuthBloc();
    when(() => bloc.state).thenReturn(const Unauthenticated());
  });

  tearDown(() => bloc.close());

  group('SignUpPage', () {
    testWidgets('renders email, password, confirm and the terms gate', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows validation errors and does not submit when empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Enter a valid email.'), findsOneWidget);
      expect(find.text('You must accept the terms to continue.'),
          findsOneWidget);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('blocks submission when the password is too weak', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      await tester.enterText(find.byType(TextFormField).at(0), 'me@real.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.enterText(find.byType(TextFormField).at(2), 'short');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Password must be at least 8 characters.'),
          findsOneWidget);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('blocks submission when the passwords do not match', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      await tester.enterText(find.byType(TextFormField).at(0), 'me@real.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Secret123');
      await tester.enterText(find.byType(TextFormField).at(2), 'Secret999');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text("Passwords don't match."), findsOneWidget);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('dispatches AuthSignUpRequested on a valid submission', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      await tester.enterText(find.byType(TextFormField).at(0), 'me@real.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Secret123');
      await tester.enterText(find.byType(TextFormField).at(2), 'Secret123');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      verify(
        () => bloc.add(
          const AuthSignUpRequested(
            email: 'me@real.com',
            password: 'Secret123',
          ),
        ),
      ).called(1);
    });

    testWidgets('shows a progress indicator while AuthLoading', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const AuthLoading());
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
