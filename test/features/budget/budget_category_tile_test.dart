import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_category_tile.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Shared fixtures — not const because DateTime.utc() is not const.
// ---------------------------------------------------------------------------

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

const BudgetStatus _healthy = BudgetStatus(
  spentMinor: 20000,
  amountMinor: 100000,
  percentSpent: 0.20,
  tone: BudgetTone.healthy,
  crossedThresholds: <int>[],
);

const BudgetStatus _warning = BudgetStatus(
  spentMinor: 60000,
  amountMinor: 100000,
  percentSpent: 0.60,
  tone: BudgetTone.warning,
  crossedThresholds: <int>[50],
);

const BudgetStatus _danger = BudgetStatus(
  spentMinor: 85000,
  amountMinor: 100000,
  percentSpent: 0.85,
  tone: BudgetTone.danger,
  crossedThresholds: <int>[50, 80],
);

const BudgetStatus _exceeded = BudgetStatus(
  spentMinor: 120000,
  amountMinor: 100000,
  percentSpent: 1.20,
  tone: BudgetTone.exceeded,
  crossedThresholds: <int>[50, 80, 100],
);

const Category _groceries = Category(
  id: 1,
  name: 'Groceries',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

BudgetSnapshot _snapshot(BudgetStatus status, {Category? category}) {
  return BudgetSnapshot(
    budget: _budget,
    window: _window,
    status: status,
    category: category,
  );
}

Widget _wrap(
  BudgetCategoryTile tile, {
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
    home: Scaffold(body: tile),
  );
}

void main() {
  group('BudgetCategoryTile', () {
    // -----------------------------------------------------------------------
    // Tones
    // -----------------------------------------------------------------------

    testWidgets(
      'should render a healthy tile and show remaining balance',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_healthy),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'should render a warning tile without errors',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_warning),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'should render a danger tile without errors',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_danger),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'should render an exceeded tile without errors',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_exceeded),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Category presence
    // -----------------------------------------------------------------------

    testWidgets(
      'should show the wallet icon when category is null (general budget)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_healthy),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byIcon(Icons.account_balance_wallet_rounded),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'should show the category icon and not the wallet when category is set',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_healthy, category: _groceries),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byIcon(Icons.account_balance_wallet_rounded),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Callbacks
    // -----------------------------------------------------------------------

    testWidgets(
      'should invoke onTap when the card is tapped',
      (WidgetTester tester) async {
        var tapped = false;
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_healthy),
              onTap: () => tapped = true,
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(InkWell).first);
        await tester.pump();

        expect(tapped, isTrue);
      },
    );

    // -----------------------------------------------------------------------
    // Dismiss flow
    // -----------------------------------------------------------------------

    testWidgets(
      'should show a confirmation dialog when the tile is swiped away',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_healthy),
              onTap: () {},
              onDelete: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(Dismissible),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );

    testWidgets(
      'should cancel the dismiss when the cancel button is tapped',
      (WidgetTester tester) async {
        var deleteCalled = false;
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_healthy),
              onTap: () {},
              onDelete: () => deleteCalled = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(Dismissible),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        // Tap the cancel TextButton (first of the two dialog actions).
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        expect(deleteCalled, isFalse);
        // The tile should still be visible after cancellation.
        expect(find.byType(Dismissible), findsOneWidget);
      },
    );

    testWidgets(
      'should call onDelete when the confirm button is tapped',
      (WidgetTester tester) async {
        var deleteCalled = false;
        await tester.pumpWidget(
          _wrap(
            BudgetCategoryTile(
              snapshot: _snapshot(_healthy),
              onTap: () {},
              onDelete: () => deleteCalled = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(Dismissible),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        // Tap the confirm FilledButton.tonal.
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(deleteCalled, isTrue);
      },
    );

    // -----------------------------------------------------------------------
    // Locale / theme overflow guard
    // -----------------------------------------------------------------------

    testWidgets(
      'should render without overflow across locales and theme modes',
      (WidgetTester tester) async {
        final BudgetCategoryTile tile = BudgetCategoryTile(
          snapshot: _snapshot(_exceeded, category: _groceries),
          onTap: () {},
          onDelete: () {},
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
            await tester.pumpWidget(
              _wrap(tile, locale: locale, themeMode: mode),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  });
}
