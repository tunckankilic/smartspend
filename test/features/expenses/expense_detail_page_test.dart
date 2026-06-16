import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_detail_bloc.dart';
import 'package:smartspend/features/expenses/presentation/pages/expense_detail_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockExpenseDetailBloc
    extends MockBloc<ExpenseDetailEvent, ExpenseDetailState>
    implements ExpenseDetailBloc {}

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
    isManual: false,
    isRecurring: true,
    recurringPeriod: RecurringPeriod.monthly,
    isPendingSync: true,
    receiptId: 9,
    note: 'Weekly shop',
    tags: const <String>['food', 'home'],
  );
}

void main() {
  late _MockExpenseDetailBloc bloc;

  setUpAll(() {
    registerFallbackValue(const ExpenseDetailRequested(id: 1));
  });

  setUp(() {
    bloc = _MockExpenseDetailBloc();
    sl.registerFactory<ExpenseDetailBloc>(() => bloc);
  });

  tearDown(() async {
    await sl.reset();
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
      home: const ExpenseDetailPage(expenseId: 1),
    );
  }

  group('ExpenseDetailPage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(const ExpenseDetailLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the expense fields once loaded', (
      WidgetTester tester,
    ) async {
      // Tall surface so the trailing delete button mounts without a scroll.
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      when(
        () => bloc.state,
      ).thenReturn(ExpenseDetailLoaded(expense: _expense()));
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Weekly shop'), findsOneWidget);
      expect(find.byType(Chip), findsNWidgets(2));
      expect(find.byIcon(Icons.autorenew_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('shows the not-found message when the expense is null', (
      WidgetTester tester,
    ) async {
      when(
        () => bloc.state,
      ).thenReturn(const ExpenseDetailLoaded(expense: null));
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('shows the error body on a hard failure', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ExpenseDetailError(failure: CacheFailure(message: 'broke')),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(
        () => bloc.state,
      ).thenReturn(ExpenseDetailLoaded(expense: _expense()));

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
