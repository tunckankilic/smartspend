import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:smartspend/features/budget/presentation/pages/budget_page.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_empty_state.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockBudgetBloc extends MockBloc<BudgetEvent, BudgetState>
    implements BudgetBloc {}

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

// Not const — DateTime.utc() is not a const expression.
final Budget _budget = Budget(
  id: 1,
  amountMinor: 100000,
  period: BudgetPeriod.monthly,
  startDate: DateTime.utc(2026, 1, 1),
  isActive: true,
);

final BudgetWindow _window = BudgetWindow(
  startUtc: DateTime.utc(2026, 6, 1),
  endUtcExclusive: DateTime.utc(2026, 7, 1),
);

const BudgetStatus _status = BudgetStatus(
  spentMinor: 25000,
  amountMinor: 100000,
  percentSpent: 0.25,
  tone: BudgetTone.healthy,
  crossedThresholds: <int>[],
);

void main() {
  late _MockBudgetBloc bloc;
  late _MockSyncCubit syncCubit;

  setUpAll(() {
    registerFallbackValue(const BudgetSubscribed());
  });

  setUp(() {
    bloc = _MockBudgetBloc();
    syncCubit = _MockSyncCubit();
    when(() => syncCubit.state).thenReturn(const SyncIdle());
    sl.registerFactory<BudgetBloc>(() => bloc);
  });

  tearDown(() async {
    await sl.reset();
    await syncCubit.close();
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
      home: BlocProvider<SyncCubit>.value(
        value: syncCubit,
        child: const BudgetPage(),
      ),
    );
  }

  group('BudgetPage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(const BudgetLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the empty-state widget when there are no budgets', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const BudgetLoaded(snapshots: <BudgetSnapshot>[]),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(BudgetEmptyState), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders the general card and FAB when budgets are loaded', (
      WidgetTester tester,
    ) async {
      final BudgetSnapshot snapshot = BudgetSnapshot(
        budget: _budget,
        window: _window,
        status: _status,
      );
      when(() => bloc.state).thenReturn(
        BudgetLoaded(
          snapshots: <BudgetSnapshot>[snapshot],
          notificationsEnabled: true,
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('shows the error icon and retry button on failure', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const BudgetError(failure: CacheFailure(message: 'broke')),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      final BudgetSnapshot snapshot = BudgetSnapshot(
        budget: _budget,
        window: _window,
        status: _status,
      );
      when(() => bloc.state).thenReturn(
        BudgetLoaded(
          snapshots: <BudgetSnapshot>[snapshot],
          notificationsEnabled: true,
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
