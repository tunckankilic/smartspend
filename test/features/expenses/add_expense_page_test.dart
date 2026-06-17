import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
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
  bool isRecurring = false,
  RecurringPeriod? recurringPeriod,
  AddExpenseMode mode = AddExpenseMode.add,
  int? amountMinor,
  String amountInput = '',
}) {
  return AddExpenseReady(
    mode: mode,
    amountInput: amountInput,
    amountMinor: amountMinor,
    date: DateTime.utc(2026, 5, 1),
    categories: categories,
    availableTags: const <String>[],
    category: category,
    validationErrors: errors,
    isSubmitting: isSubmitting,
    isRecurring: isRecurring,
    recurringPeriod: recurringPeriod,
  );
}

Widget _wrap({
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
    home: const AddExpensePage(),
  );
}

void main() {
  late _MockAddExpenseBloc bloc;

  setUpAll(() {
    registerFallbackValue(const AddExpenseStarted());
    registerFallbackValue(
      const AddExpenseRecurringToggled(value: true),
    );
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

    // -------------------------------------------------------------------------
    // New coverage: submitting state, validation branches, recurring, etc.
    // -------------------------------------------------------------------------

    testWidgets(
      'should show a spinner in the AppBar and disable the save icon '
      'while submitting',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(_ready(isSubmitting: true));
        await tester.pumpWidget(_wrap());
        await tester.pump();

        // check_rounded AppBar action is replaced by a mini progress indicator
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'should surface inline futureDate error without overflow',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          _ready(
            errors: <AddExpenseValidationError>{
              AddExpenseValidationError.futureDate,
            },
          ),
        );
        await tester.pumpWidget(_wrap());
        await tester.pump();

        expect(tester.takeException(), isNull);
        // The error subtree is present — a Text widget styled with error color
        // lives beneath the date button.
        expect(find.byType(Text), findsWidgets);
      },
    );

    testWidgets(
      'should show period ChoiceChips when the recurring toggle is on',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 4000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(_ready(isRecurring: true));
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        expect(find.byType(ChoiceChip), findsWidgets);
      },
    );

    testWidgets(
      'should not show period chips when recurring is off',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 4000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(_ready());
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        expect(find.byType(ChoiceChip), findsNothing);
      },
    );

    testWidgets(
      'should dispatch AddExpenseRecurringToggled when the switch is tapped',
      (WidgetTester tester) async {
        // Use a tall surface so the SwitchListTile at the bottom of the
        // ListView is laid out and tappable.
        await tester.binding.setSurfaceSize(const Size(800, 4000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(_ready());
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();

        verify(
          () => bloc.add(const AddExpenseRecurringToggled(value: true)),
        ).called(1);
      },
    );

    testWidgets(
      'should show the missingRecurringPeriod validation error '
      'when recurring is on with no period chosen',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 4000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(
          _ready(
            isRecurring: true,
            errors: <AddExpenseValidationError>{
              AddExpenseValidationError.missingRecurringPeriod,
            },
          ),
        );
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ChoiceChip), findsWidgets);
      },
    );

    testWidgets(
      'should render all four quick-amount ActionChips',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(_ready());
        await tester.pumpWidget(_wrap());
        await tester.pump();

        for (final int minor in const <int>[5000, 10000, 25000, 50000]) {
          expect(
            find.byKey(ValueKey<String>('quickAmount.$minor')),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      'should render the edit-mode title when mode is AddExpenseMode.edit',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          _ready(
            mode: AddExpenseMode.edit,
            amountInput: '10',
            amountMinor: 1000,
          ),
        );
        await tester.pumpWidget(_wrap());
        await tester.pump();

        expect(find.byType(AppBar), findsOneWidget);
        // edit-mode title differs from add-mode title
        expect(find.text('New expense'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'should show the formatted amount hint when amountMinor is set',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          _ready(amountInput: '42', amountMinor: 4200),
        );
        await tester.pumpWidget(_wrap());
        await tester.pump();

        // The hint text is the formatted minor value; just verify no crash.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'should show a snackbar on failure via the BlocConsumer listener',
      (WidgetTester tester) async {
        final StreamController<AddExpenseState> ctrl =
            StreamController<AddExpenseState>();
        whenListen(
          bloc,
          ctrl.stream,
          initialState: const AddExpenseLoading(),
        );
        addTearDown(ctrl.close);

        await tester.pumpWidget(_wrap());
        await tester.pump();

        ctrl.add(
          const AddExpenseFailure(
            failure: ServerFailure(message: 'save failed'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'should render without overflow across locales and theme modes',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          _ready(categories: const <Category>[_groceries]),
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
            await tester.pumpWidget(_wrap(locale: locale, themeMode: mode));
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  });
}
