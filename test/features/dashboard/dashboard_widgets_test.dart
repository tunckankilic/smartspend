import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_empty_state.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_quick_actions.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

GoRouter _router(Widget child) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: child)),
      GoRoute(path: '/scan', builder: (_, _) => const _Stub('scan')),
      GoRoute(
        path: '/expenses',
        builder: (_, _) => const _Stub('expenses'),
        routes: <RouteBase>[
          GoRoute(path: 'new', builder: (_, _) => const _Stub('new')),
        ],
      ),
      GoRoute(path: '/budget', builder: (_, _) => const _Stub('budget')),
    ],
  );
}

Widget _wrap(Widget child) {
  return MaterialApp.router(
    routerConfig: _router(child),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
}

void main() {
  testWidgets(
    'DashboardQuickActions should render the four primary action tiles',
    (tester) async {
      await tester.pumpWidget(_wrap(const DashboardQuickActions()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('quickAction.scan')), findsOne);
      expect(find.byKey(const ValueKey<String>('quickAction.add')), findsOne);
      expect(
        find.byKey(const ValueKey<String>('quickAction.budget')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey<String>('quickAction.report')),
        findsOne,
      );
    },
  );

  testWidgets(
    'DashboardEmptyState should render the empty headline + actions',
    (tester) async {
      await tester.pumpWidget(_wrap(const DashboardEmptyState()));
      await tester.pumpAndSettle();
      // Headline copy comes from AppLocalizations (English in this harness).
      expect(find.text('No expenses yet'), findsOne);
      // Two CTAs: scan + add manually.
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOne);
      expect(find.byIcon(Icons.add_rounded), findsOne);
    },
  );
}

class _Stub extends StatelessWidget {
  const _Stub(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}
