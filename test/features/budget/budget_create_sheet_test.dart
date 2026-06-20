import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_create_sheet.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockListCategories extends Mock implements ListCategoriesUseCase {}

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
    home: const Scaffold(body: BudgetCreateSheet()),
  );
}

Widget _hostWrap({
  required void Function(BudgetSheetResult?) onResult,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData.light(),
    home: Builder(
      builder: (BuildContext ctx) => ElevatedButton(
        key: const Key('open'),
        onPressed: () async {
          final BudgetSheetResult? result = await BudgetCreateSheet.show(ctx);
          onResult(result);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  late _MockListCategories listCategories;

  setUpAll(() {
    registerFallbackValue(const ListCategoriesParams());
  });

  setUp(() {
    listCategories = _MockListCategories();
    when(
      () => listCategories(const ListCategoriesParams()),
    ).thenAnswer(
      (_) async => const Right<Failure, List<Category>>(<Category>[]),
    );
    sl.registerFactory<ListCategoriesUseCase>(() => listCategories);
  });

  tearDown(() async {
    await sl.reset();
  });

  group('BudgetCreateSheet', () {
    testWidgets(
      'should render the amount field, period chips and submit button',
      (WidgetTester tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
        // 2 period chips (weekly/monthly) + 1 "General" category chip.
        // `yearly` is held out of v1 (remote budgets_period_check rejects it).
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(find.byType(FilledButton), findsOneWidget);
        // Create mode: no delete button.
        expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      },
    );

    testWidgets(
      'should prefix the amount field with the default currency symbol, '
      'not a dollar icon',
      (WidgetTester tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        // Default currency is TRY → ₺; the old hardcoded "$" icon is gone.
        expect(find.textContaining('₺'), findsOneWidget);
        expect(find.byIcon(Icons.attach_money_rounded), findsNothing);
      },
    );

    testWidgets(
      'should pop a BudgetSheetResult with the entered amount',
      (WidgetTester tester) async {
        BudgetSheetResult? result;
        await tester.pumpWidget(_hostWrap(onResult: (r) => result = r));
        await tester.pump();

        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, '100');
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result?.amountMinor, 10000);
        expect(result?.deleted, isFalse);
      },
    );

    testWidgets(
      'should show a validation error and stay open when amount is empty',
      (WidgetTester tester) async {
        BudgetSheetResult? result;
        await tester.pumpWidget(_hostWrap(onResult: (r) => result = r));
        await tester.pump();

        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();

        // Do NOT enter any amount — tap submit immediately.
        await tester.tap(find.byType(FilledButton));
        await tester.pump();

        // Sheet must remain open: result is still null.
        expect(result, isNull);
        expect(find.byType(BudgetCreateSheet), findsOneWidget);
      },
    );

    testWidgets(
      'should render without overflow across locales and theme modes',
      (WidgetTester tester) async {
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
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  });
}
