import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_circular_progress.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_empty_state.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('BudgetCircularProgress', () {
    testWidgets('should render a child overlay inside the ring',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const BudgetCircularProgress(
            percentSpent: 0.5,
            tone: BudgetTone.warning,
            child: Text('50%'),
          ),
        ),
      );
      expect(find.text('50%'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('BudgetEmptyState', () {
    testWidgets('tapping the CTA fires the onCreate callback',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(BudgetEmptyState(onCreate: () => taps += 1)),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
