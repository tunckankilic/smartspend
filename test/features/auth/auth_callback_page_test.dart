import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/pages/auth_callback_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

const AppUser _user = AppUser(id: 'u1', email: 'jane@example.com');

GoRouter _router() {
  return GoRouter(
    initialLocation: '/auth/callback',
    routes: <RouteBase>[
      GoRoute(
        path: '/auth/callback',
        builder: (BuildContext _, GoRouterState _) =>
            const AuthCallbackPage(),
      ),
      GoRoute(
        path: '/',
        builder: (BuildContext _, GoRouterState _) =>
            const Scaffold(body: Text('Home')),
      ),
    ],
  );
}

void main() {
  late _MockAuthBloc bloc;

  setUp(() {
    bloc = _MockAuthBloc();
  });

  Widget wrap() {
    return BlocProvider<AuthBloc>.value(
      value: bloc,
      child: MaterialApp.router(
        routerConfig: _router(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
  }

  group('AuthCallbackPage', () {
    testWidgets('renders the loading spinner and message', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const AuthLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(AuthCallbackPage)),
      );
      expect(find.text(l.authCallbackLoading), findsOneWidget);
    });

    testWidgets('navigates to / once authenticated', (
      WidgetTester tester,
    ) async {
      final StreamController<AuthState> controller =
          StreamController<AuthState>();
      whenListen(bloc, controller.stream, initialState: const AuthLoading());
      addTearDown(controller.close);

      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.add(const Authenticated(user: _user));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(AuthCallbackPage), findsNothing);
    });
  });
}
