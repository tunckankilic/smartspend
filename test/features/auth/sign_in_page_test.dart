import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/pages/sign_in_page.dart';
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
      child: const SignInPage(),
    ),
  );
}

void main() {
  late _MockAuthBloc bloc;

  setUpAll(() {
    registerFallbackValue(
      const AuthSignInRequested(email: 'a@b.com', password: 'x'),
    );
  });

  setUp(() {
    bloc = _MockAuthBloc();
    when(() => bloc.state).thenReturn(const Unauthenticated());
  });

  tearDown(() => bloc.close());

  group('SignInPage', () {
    testWidgets('renders email, password and the sign-in button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows validation errors and does not submit when empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Enter a valid email.'), findsOneWidget);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('dispatches AuthSignInRequested with the entered credentials', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(bloc));

      await tester.enterText(
        find.byType(TextFormField).first,
        'me@real.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'secret123');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      verify(
        () => bloc.add(
          const AuthSignInRequested(
            email: 'me@real.com',
            password: 'secret123',
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
