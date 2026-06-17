import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_insight_banner.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

const Category _groceries = Category(
  id: 1,
  name: 'Groceries',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

GoRouter _router(Widget child) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/expenses',
        builder: (_, _) => const _Stub('expenses'),
      ),
      GoRoute(
        path: '/budget',
        builder: (_, _) => const _Stub('budget'),
      ),
    ],
  );
}

Widget _wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MaterialApp.router(
    routerConfig: _router(child),
    locale: locale,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    themeMode: themeMode,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
}

DashboardInsightBanner _banner(
  DashboardInsight insight, {
  List<Category> categories = const <Category>[],
}) {
  return DashboardInsightBanner(insight: insight, categories: categories);
}

void main() {
  group('DashboardInsightBanner', () {
    group('CategorySpikeInsight', () {
      testWidgets(
        'should show the category icon and a chevron when category is found',
        (WidgetTester tester) async {
          const CategorySpikeInsight insight = CategorySpikeInsight(
            categoryId: 1,
            deltaPercent: 45,
          );
          await tester.pumpWidget(
            _wrap(
              _banner(insight, categories: const <Category>[_groceries]),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'should fall back gracefully when the category is not in the list',
        (WidgetTester tester) async {
          const CategorySpikeInsight insight = CategorySpikeInsight(
            categoryId: 99,
            deltaPercent: 30,
          );
          // Empty category list → cat == null → uses fallback icon.
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();

          expect(find.byType(Card), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    });

    group('BudgetWarningInsight', () {
      testWidgets(
        'should show the warning icon when budget is not yet exceeded',
        (WidgetTester tester) async {
          const BudgetWarningInsight insight = BudgetWarningInsight(
            budgetId: 1,
            percentSpent: 85,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();

          expect(
            find.byIcon(Icons.warning_amber_rounded),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'should show the error icon when budget is exceeded (≥ 100 %)',
        (WidgetTester tester) async {
          const BudgetWarningInsight insight = BudgetWarningInsight(
            budgetId: 1,
            percentSpent: 110,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'should resolve category name when a categoryId is provided',
        (WidgetTester tester) async {
          const BudgetWarningInsight insight = BudgetWarningInsight(
            budgetId: 1,
            percentSpent: 90,
            categoryId: 1,
          );
          await tester.pumpWidget(
            _wrap(
              _banner(insight, categories: const <Category>[_groceries]),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    });

    group('BudgetAchievementInsight', () {
      testWidgets(
        'should show the trophy icon and a chevron to the budget page',
        (WidgetTester tester) async {
          const BudgetAchievementInsight insight = BudgetAchievementInsight(
            budgetId: 1,
            percentElapsed: 80,
            percentSpent: 40,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'should use the category name when categoryId matches a known category',
        (WidgetTester tester) async {
          const BudgetAchievementInsight insight = BudgetAchievementInsight(
            budgetId: 1,
            percentElapsed: 80,
            percentSpent: 35,
            categoryId: 1,
          );
          await tester.pumpWidget(
            _wrap(
              _banner(insight, categories: const <Category>[_groceries]),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    });

    group('FrequencyInsight', () {
      testWidgets(
        'should show the repeat icon and no chevron (onTap is null)',
        (WidgetTester tester) async {
          const FrequencyInsight insight = FrequencyInsight(
            tag: 'coffee',
            count: 8,
            totalMinor: 24000,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    });

    group('DayOfWeekInsight', () {
      testWidgets(
        'should show the calendar icon and no chevron (onTap is null)',
        (WidgetTester tester) async {
          const DayOfWeekInsight insight = DayOfWeekInsight(
            weekday: DateTime.friday,
            deltaPercent: 42,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'should handle all 7 ISO weekdays without errors',
        (WidgetTester tester) async {
          for (int day = DateTime.monday;
              day <= DateTime.sunday;
              day++) {
            final DayOfWeekInsight insight = DayOfWeekInsight(
              weekday: day,
              deltaPercent: 35,
            );
            await tester.pumpWidget(_wrap(_banner(insight)));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        },
      );
    });

    group('Tone colors', () {
      testWidgets(
        'should render warning tone (CategorySpike) without overflow',
        (WidgetTester tester) async {
          const CategorySpikeInsight insight = CategorySpikeInsight(
            categoryId: 1,
            deltaPercent: 55,
            tone: DashboardInsightTone.warning,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'should render positive tone (BudgetAchievement) without overflow',
        (WidgetTester tester) async {
          const BudgetAchievementInsight insight = BudgetAchievementInsight(
            budgetId: 1,
            percentElapsed: 75,
            percentSpent: 30,
            tone: DashboardInsightTone.positive,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'should render info tone (DayOfWeek) without overflow',
        (WidgetTester tester) async {
          const DayOfWeekInsight insight = DayOfWeekInsight(
            weekday: DateTime.wednesday,
            deltaPercent: 31,
            tone: DashboardInsightTone.info,
          );
          await tester.pumpWidget(_wrap(_banner(insight)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    });

    testWidgets(
      'should render without overflow across locales and theme modes',
      (WidgetTester tester) async {
        const DayOfWeekInsight insight = DayOfWeekInsight(
          weekday: DateTime.monday,
          deltaPercent: 40,
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
              _wrap(_banner(insight), locale: locale, themeMode: mode),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  });
}

class _Stub extends StatelessWidget {
  const _Stub(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}
