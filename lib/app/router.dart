import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/app/widgets/main_scaffold.dart';
import 'package:smartspend/core/services/onboarding_flag_store.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/auth/presentation/pages/sign_in_page.dart';
import 'package:smartspend/features/budget/presentation/pages/budget_page.dart';
import 'package:smartspend/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:smartspend/features/expenses/presentation/pages/expense_list_page.dart';
import 'package:smartspend/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:smartspend/features/scan/presentation/pages/scan_page.dart';
import 'package:smartspend/features/settings/presentation/pages/settings_page.dart';

/// Stable GoRouter keys for navigator hot-restart safety.
final GlobalKey<NavigatorState> _rootKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// Build the app-wide [GoRouter].
///
/// [authBloc] drives the redirect logic — the router subscribes to its
/// stream so a session change repaints navigation immediately.
GoRouter buildRouter({
  required AuthBloc authBloc,
  required OnboardingFlagStore onboardingFlagStore,
}) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    debugLogDiagnostics: kDebugMode,
    refreshListenable: _BlocListenable(authBloc.stream),
    redirect: (BuildContext context, GoRouterState state) {
      final AuthState authState = authBloc.state;
      final String location = state.matchedLocation;

      final bool onboardingDone = onboardingFlagStore.isComplete;
      final bool atOnboarding = location.startsWith('/onboarding');
      final bool atAuth = location.startsWith('/auth');

      // 1. Force first-launch users to onboarding.
      if (!onboardingDone && !atOnboarding) {
        return '/onboarding';
      }
      // 2. Once onboarding is done, keep them out of it.
      if (onboardingDone && atOnboarding) {
        return '/';
      }
      // 3. Unauthenticated users only see the auth tree.
      if (authState is Unauthenticated && !atAuth) {
        return '/auth/sign-in';
      }
      // 4. Authenticated users skip the auth tree.
      if (authState is Authenticated && atAuth) {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        builder: (BuildContext c, GoRouterState s) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/auth/sign-in',
        builder: (BuildContext c, GoRouterState s) => const SignInPage(),
      ),
      // /auth/sign-up, /auth/forgot-password, /auth/callback land in Sprint 8.
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) {
          return MainScaffold(navigationShell: shell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (BuildContext c, GoRouterState s) =>
                    const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/expenses',
                builder: (BuildContext c, GoRouterState s) =>
                    const ExpenseListPage(),
                routes: <RouteBase>[
                  // Detail route — Sprint 3 will build out the real page.
                  GoRoute(
                    path: ':id',
                    builder: (BuildContext c, GoRouterState s) =>
                        const ExpenseListPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/scan',
                builder: (BuildContext c, GoRouterState s) => const ScanPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/budget',
                builder: (BuildContext c, GoRouterState s) =>
                    const BudgetPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (BuildContext c, GoRouterState s) =>
                    const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext c, GoRouterState s) =>
        Scaffold(body: Center(child: Text(s.error?.toString() ?? '404'))),
  );
}

/// Adapter that turns a Bloc's state [Stream] into a [Listenable] so
/// [GoRouter.refreshListenable] can re-evaluate redirects on state changes.
class _BlocListenable extends ChangeNotifier {
  _BlocListenable(Stream<Object?> stream) {
    _subscription =
        stream.asBroadcastStream().listen((Object? _) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
