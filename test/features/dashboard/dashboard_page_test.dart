import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:smartspend/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_bar_chart.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_empty_state.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

const Category _groceries = Category(
  id: 1,
  name: 'Groceries',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

const DashboardSnapshot _snapshot = DashboardSnapshot(
  currency: 'TRY',
  currentTotalMinor: 12500,
  previousTotalMinor: 10000,
  byCategoryCurrent: <int, int>{1: 12500},
  byCategoryPrevious: <int, int>{1: 10000},
  dailyTotals: <DateTime, int>{},
  recentExpenses: <Expense>[],
  topCategoryId: 1,
  expenseCount: 3,
);

GoRouter _router(Widget child) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext _, GoRouterState _) => child,
      ),
      GoRoute(
        path: '/scan',
        builder: (BuildContext _, GoRouterState _) =>
            const Scaffold(body: Text('scan')),
      ),
      GoRoute(
        path: '/budget',
        builder: (BuildContext _, GoRouterState _) =>
            const Scaffold(body: Text('budget')),
      ),
      GoRoute(
        path: '/expenses',
        builder: (BuildContext _, GoRouterState _) =>
            const Scaffold(body: Text('expenses')),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            builder: (BuildContext _, GoRouterState _) =>
                const Scaffold(body: Text('new')),
          ),
        ],
      ),
    ],
  );
}

void main() {
  late _MockDashboardBloc bloc;
  late _MockSyncCubit syncCubit;

  setUpAll(() {
    registerFallbackValue(const DashboardSubscribed());
  });

  setUp(() {
    bloc = _MockDashboardBloc();
    syncCubit = _MockSyncCubit();
    when(() => syncCubit.state).thenReturn(const SyncIdle());
    sl.registerFactory<DashboardBloc>(() => bloc);
  });

  tearDown(() async {
    await sl.reset();
    await syncCubit.close();
  });

  Widget wrap({
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      routerConfig: _router(
        BlocProvider<SyncCubit>.value(
          value: syncCubit,
          child: const DashboardPage(),
        ),
      ),
    );
  }

  group('DashboardPage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(
        const DashboardLoading(period: DashboardPeriod.thisMonth()),
      );
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the summary, charts and recent list once loaded', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const DashboardLoaded(
          period: DashboardPeriod.thisMonth(),
          snapshot: _snapshot,
          insight: null,
          categories: <Category>[_groceries],
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(DashboardBarChart), findsOneWidget);
    });

    testWidgets('shows the empty state when the snapshot has no expenses', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const DashboardLoaded(
          period: DashboardPeriod.thisMonth(),
          snapshot: DashboardSnapshot.empty,
          insight: null,
          categories: <Category>[],
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(DashboardEmptyState), findsOneWidget);
    });

    testWidgets('shows the error view with a retry action on failure', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const DashboardError(
          period: DashboardPeriod.thisMonth(),
          failure: CacheFailure(message: 'broke'),
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const DashboardLoaded(
          period: DashboardPeriod.thisMonth(),
          snapshot: _snapshot,
          insight: null,
          categories: <Category>[_groceries],
        ),
      );

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
