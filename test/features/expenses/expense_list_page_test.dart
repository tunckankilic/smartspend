import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_list_bloc.dart';
import 'package:smartspend/features/expenses/presentation/pages/expense_list_page.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockExpenseListBloc
    extends MockBloc<ExpenseListEvent, ExpenseListState>
    implements ExpenseListBloc {}

class _MockListCategories extends Mock implements ListCategoriesUseCase {}

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

const Category _groceries = Category(
  id: 1,
  name: 'Groceries',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

Expense _expense() {
  return Expense(
    id: 1,
    amount: 4250,
    category: _groceries,
    date: DateTime.utc(2026, 5, 20),
    currency: 'TRY',
    isManual: true,
    isRecurring: true,
    isPendingSync: true,
  );
}

const ExpenseSummary _summary = ExpenseSummary(
  totalMinor: 4250,
  currency: 'TRY',
  byCategory: <int, int>{1: 4250},
  count: 1,
);

void main() {
  late _MockExpenseListBloc bloc;
  late _MockListCategories listCategories;
  late _MockSyncCubit syncCubit;

  setUpAll(() {
    registerFallbackValue(const ExpensesSubscribed());
    registerFallbackValue(const ListCategoriesParams());
  });

  setUp(() {
    bloc = _MockExpenseListBloc();
    listCategories = _MockListCategories();
    syncCubit = _MockSyncCubit();

    when(() => syncCubit.state).thenReturn(const SyncIdle());
    when(() => listCategories(any())).thenAnswer(
      (_) async =>
          const Right<Failure, List<Category>>(<Category>[_groceries]),
    );

    sl
      ..registerFactory<ExpenseListBloc>(() => bloc)
      ..registerFactory<ListCategoriesUseCase>(() => listCategories);
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
        child: const ExpenseListPage(),
      ),
    );
  }

  group('ExpenseListPage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(const ExpenseListLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the summary and the expense row once loaded', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ExpenseListLoaded(
          expenses: <Expense>[],
          summary: _summary,
          filter: ExpenseFilter.empty,
        ).copyWith(expenses: <Expense>[_expense()]),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsWidgets);
      expect(find.byType(Dismissible), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byIcon(Icons.autorenew_rounded), findsOneWidget);
    });

    testWidgets('shows the empty state placeholder when there are no rows', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ExpenseListLoaded(
          expenses: <Expense>[],
          summary: ExpenseSummary.empty,
          filter: ExpenseFilter.empty,
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
      expect(find.byType(Dismissible), findsNothing);
    });

    testWidgets('shows the error body on a hard failure', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ExpenseListError(
          failure: CacheFailure(message: 'broke'),
          filter: ExpenseFilter.empty,
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        ExpenseListLoaded(
          expenses: <Expense>[_expense()],
          summary: _summary,
          filter: ExpenseFilter.empty,
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
