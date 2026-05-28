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
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/presentation/pages/add_expense_page.dart';
import 'package:smartspend/features/expenses/presentation/pages/expense_detail_page.dart';
import 'package:smartspend/features/expenses/presentation/pages/expense_list_page.dart';
import 'package:smartspend/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:smartspend/features/receipts/presentation/pages/receipt_archive_page.dart';
import 'package:smartspend/features/receipts/presentation/pages/receipt_detail_page.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/presentation/pages/scan_page.dart';
import 'package:smartspend/features/scan/presentation/pages/scan_result_page.dart';
import 'package:smartspend/features/settings/presentation/pages/settings_page.dart';
import 'package:smartspend/features/split/presentation/pages/split_page.dart';

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

      // Receipt edit screen — opened on top of the shell so the user gets
      // full screen for review and is forced to consciously cancel/save
      // instead of swiping back into a partial edit.
      GoRoute(
        path: '/scan/result',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) {
          final ScannedReceipt receipt = s.extra! as ScannedReceipt;
          return ScanResultPage(receipt: receipt);
        },
      ),
      // Manual-entry / edit form — also pushed on the root navigator so
      // the bottom tab bar is hidden while the user is filling in the
      // form.
      GoRoute(
        path: '/expenses/new',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => const AddExpensePage(),
      ),
      GoRoute(
        path: '/expenses/:id/edit',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) {
          final Expense expense = s.extra! as Expense;
          return AddExpensePage(expense: expense);
        },
      ),
      // Sprint 7 — Hesap Bölüşme. Pushed on the root navigator (full
      // screen, no bottom tabs) so the user finishes the split flow
      // without being able to wander off into other tabs mid-edit.
      GoRoute(
        path: '/split/:receiptId',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) {
          final int id =
              int.tryParse(s.pathParameters['receiptId'] ?? '') ?? -1;
          return SplitPage(receiptId: id);
        },
      ),
      // Sprint 7 — Fiş Arşivi. Top-level read-only browsing surface;
      // entered from Settings / Dashboard quick actions.
      GoRoute(
        path: '/receipts',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) =>
            const ReceiptArchivePage(),
      ),
      GoRoute(
        path: '/receipts/:id',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) {
          final int id = int.tryParse(s.pathParameters['id'] ?? '') ?? -1;
          return ReceiptDetailPage(receiptId: id);
        },
      ),
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
                builder: (BuildContext c, GoRouterState s) {
                  final int? catId = int.tryParse(
                    s.uri.queryParameters['categoryId'] ?? '',
                  );
                  return ExpenseListPage(initialCategoryId: catId);
                },
                routes: <RouteBase>[
                  GoRoute(
                    path: ':id',
                    builder: (BuildContext c, GoRouterState s) {
                      final int id =
                          int.tryParse(s.pathParameters['id'] ?? '') ?? -1;
                      return ExpenseDetailPage(expenseId: id);
                    },
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
