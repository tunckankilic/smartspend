import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/presentation/bloc/add_expense_bloc.dart';
import 'package:smartspend/features/expenses/presentation/pages/add_expense_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockAddExpenseBloc extends MockBloc<AddExpenseEvent, AddExpenseState>
    implements AddExpenseBloc {}

const Category _groceries = Category(
  id: 1,
  name: 'Groceries',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

AddExpenseReady _ready({
  Category? category,
  List<Category> categories = const <Category>[],
  Set<AddExpenseValidationError> errors = const <AddExpenseValidationError>{},
  bool isSubmitting = false,
}) {
  return AddExpenseReady(
    mode: AddExpenseMode.add,
    amountInput: '',
    amountMinor: null,
    date: DateTime.utc(2026, 5, 1),
    categories: categories,
    availableTags: const <String>[],
    category: category,
    validationErrors: errors,
    isSubmitting: isSubmitting,
  );
}

Widget _wrap() {
  return const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale('en'),
    home: AddExpensePage(),
  );
}

void main() {
  late _MockAddExpenseBloc bloc;

  setUpAll(() {
    registerFallbackValue(const AddExpenseStarted());
  });

  setUp(() {
    bloc = _MockAddExpenseBloc();
    sl.registerFactory<AddExpenseBloc>(() => bloc);
  });

  tearDown(() async {
    await sl.reset();
  });

  group('AddExpensePage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(const AddExpenseLoading());
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the form fields once ready', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(_ready());
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('New expense'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('categoryTile.more')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('renders category tiles and dispatches selection on tap', (
      WidgetTester tester,
    ) async {
      when(
        () => bloc.state,
      ).thenReturn(_ready(categories: const <Category>[_groceries]));
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('Groceries'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('categoryTile.1')));
      await tester.pump();

      verify(
        () => bloc.add(
          const AddExpenseCategorySelected(category: _groceries),
        ),
      ).called(1);
    });

    testWidgets('surfaces inline validation errors from the state', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        _ready(
          errors: <AddExpenseValidationError>{
            AddExpenseValidationError.invalidAmount,
            AddExpenseValidationError.missingCategory,
          },
        ),
      );
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('Amount must be greater than zero.'), findsOneWidget);
      expect(find.text('Pick a category.'), findsOneWidget);
    });

    testWidgets('typing an amount dispatches AddExpenseAmountChanged', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(_ready());
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '42');
      await tester.pump();

      verify(
        () => bloc.add(const AddExpenseAmountChanged(input: '42')),
      ).called(1);
    });

    testWidgets('tapping save dispatches AddExpenseSubmitted', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(_ready());
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();

      verify(() => bloc.add(const AddExpenseSubmitted())).called(1);
    });
  });
}
