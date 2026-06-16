import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_filter_sheet.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

const List<Category> _categories = <Category>[
  Category(
    id: 1,
    name: 'Groceries',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    isCustom: false,
  ),
];

Widget _wrap({
  ExpenseFilter initial = ExpenseFilter.empty,
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
    home: Scaffold(
      body: ExpenseFilterSheet(
        initial: initial,
        categories: _categories,
      ),
    ),
  );
}

Widget _hostWrap({
  required void Function(ExpenseFilter?) onResult,
  ExpenseFilter initial = ExpenseFilter.empty,
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
          final ExpenseFilter? result = await ExpenseFilterSheet.show(
            ctx,
            initial: initial,
            categories: _categories,
          );
          onResult(result);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  group('ExpenseFilterSheet', () {
    testWidgets(
      'should render date buttons, amount fields and action buttons',
      (WidgetTester tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // 2 date OutlinedButton.icon + 1 clear OutlinedButton.
      expect(find.byType(OutlinedButton), findsNWidgets(3));
      // Apply (FilledButton) and 2 TextFields for min/max amount.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      // Category chip from fixture.
      expect(find.byType(FilterChip), findsOneWidget);
    });

    testWidgets('should pop the applied filter when apply is tapped', (
      WidgetTester tester,
    ) async {
      ExpenseFilter? result;
      await tester.pumpWidget(
        _hostWrap(onResult: (r) => result = r),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // The sheet pops an ExpenseFilter (empty since nothing was changed).
      expect(result, isA<ExpenseFilter>());
      expect(result?.isUnfiltered, isTrue);
    });

    testWidgets('should pop ExpenseFilter.empty when clear is tapped', (
      WidgetTester tester,
    ) async {
      ExpenseFilter? result;
      // Start with a non-empty initial filter.
      const ExpenseFilter initial = ExpenseFilter(
        categoryIds: <int>{1},
        sortOrder: ExpenseSortOrder.amountDesc,
      );
      await tester.pumpWidget(
        _hostWrap(onResult: (r) => result = r, initial: initial),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      // Tap the Clear (OutlinedButton) — first of the three.
      await tester.tap(find.byType(OutlinedButton).last);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result?.isUnfiltered, isTrue);
    });

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
