import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/presentation/widgets/category_picker_sheet.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

const Category _groceries = Category(
  id: 1,
  name: 'Groceries',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

const Category _transport = Category(
  id: 2,
  name: 'Transport',
  icon: 'directions_car',
  color: 0xFF2196F3,
  isCustom: false,
);

const List<Category> _categories = <Category>[_groceries, _transport];

Widget _wrap({
  bool allowCreate = false,
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
      body: CategoryPickerSheet(
        categories: _categories,
        allowCreate: allowCreate,
      ),
    ),
  );
}

Widget _hostWrap({
  required void Function(CategoryPickerResult?) onResult,
  bool allowCreate = false,
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
          final CategoryPickerResult? result = await CategoryPickerSheet.show(
            ctx,
            categories: _categories,
            allowCreate: allowCreate,
          );
          onResult(result);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  group('CategoryPickerSheet', () {
    testWidgets(
      'should render the search field and one tile per category',
      (WidgetTester tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
        expect(find.byType(GridView), findsOneWidget);
        // 2 category tiles rendered.
        expect(find.byType(InkWell), findsNWidgets(2));
        // allowCreate: false — no add button.
        expect(find.byType(OutlinedButton), findsNothing);
      },
    );

    testWidgets('should pop CategoryPickerSelected when a tile is tapped', (
      WidgetTester tester,
    ) async {
      CategoryPickerResult? result;
      await tester.pumpWidget(
        _hostWrap(onResult: (r) => result = r),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      // Tap the Groceries tile by its data-driven text label.
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();

      expect(result, isA<CategoryPickerSelected>());
      expect((result! as CategoryPickerSelected).category.id, 1);
    });

    testWidgets(
      'should show the add-category button when allowCreate is true',
      (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(allowCreate: true));
      await tester.pumpAndSettle();

      expect(find.byType(OutlinedButton), findsOneWidget);
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
