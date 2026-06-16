import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/presentation/widgets/split_assignment_sheet.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

const List<Participant> _participants = <Participant>[
  Participant(id: 'p1', name: 'Alice'),
  Participant(id: 'p2', name: 'Bob'),
];

Widget _wrap({
  List<String> selected = const <String>[],
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
      body: SplitAssignmentSheet(
        itemName: 'Milk',
        participants: _participants,
        selected: selected,
      ),
    ),
  );
}

/// Opens the sheet via [SplitAssignmentSheet.show] and returns the
/// captured result via the [onResult] callback.
Widget _hostWrap({
  required void Function(List<String>?) onResult,
  List<String> selected = const <String>[],
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
          final List<String>? result = await SplitAssignmentSheet.show(
            ctx,
            itemName: 'Milk',
            participants: _participants,
            selected: selected,
          );
          onResult(result);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  group('SplitAssignmentSheet', () {
    testWidgets(
      'should render a checkbox row per participant and the save button',
      (WidgetTester tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(find.byKey(const Key('split.assign.p1')), findsOneWidget);
      expect(find.byKey(const Key('split.assign.p2')), findsOneWidget);
      expect(find.byKey(const Key('split.assign.save')), findsOneWidget);
    });

    testWidgets('should return selected ids when save is tapped', (
      WidgetTester tester,
    ) async {
      List<String>? result;
      await tester.pumpWidget(
        _hostWrap(selected: const <String>[], onResult: (r) => result = r),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      // Check 'p1' checkbox.
      await tester.tap(find.byKey(const Key('split.assign.p1')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('split.assign.save')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, contains('p1'));
      expect(result, isNot(contains('p2')));
    });

    testWidgets('should return an empty list when clear is tapped', (
      WidgetTester tester,
    ) async {
      List<String>? result;
      await tester.pumpWidget(
        _hostWrap(
          selected: const <String>['p1', 'p2'],
          onResult: (r) => result = r,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      // Tap the Clear (OutlinedButton) — first button in the Row.
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, isEmpty);
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
    });
  });
}
