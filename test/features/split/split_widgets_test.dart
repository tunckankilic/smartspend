import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/presentation/widgets/split_participant_chips.dart';
import 'package:smartspend/features/split/presentation/widgets/split_summary_card.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

SplitSession _session({
  List<Participant> participants = const <Participant>[],
}) {
  return SplitSession(
    receiptId: 1,
    storeName: 'Migros',
    receiptDate: DateTime.utc(2026, 5, 28),
    currency: 'TRY',
    totalMinor: 30000,
    items: const <Object>[].cast(),
    participants: participants,
    assignments: const <int, List<String>>{},
    splitType: SplitType.equal,
  );
}

void main() {
  group('SplitParticipantChips', () {
    testWidgets('should show empty hint when participants list is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          SplitParticipantChips(
            participants: const <Participant>[],
            onAdded: (String _) {},
            onRemoved: (String _) {},
          ),
        ),
      );
      expect(find.text('Add'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('should fire onAdded when Add button is tapped',
        (WidgetTester tester) async {
      final List<String> added = <String>[];
      await tester.pumpWidget(
        _wrap(
          SplitParticipantChips(
            participants: const <Participant>[],
            onAdded: added.add,
            onRemoved: (String _) {},
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('split.participant.input')),
        'Ali',
      );
      await tester.tap(find.byKey(const Key('split.participant.add')));
      await tester.pumpAndSettle();
      expect(added, <String>['Ali']);
    });

    testWidgets('should render a chip per participant',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          SplitParticipantChips(
            participants: const <Participant>[
              Participant(id: 'p1', name: 'Ali'),
              Participant(id: 'p2', name: 'Mehmet'),
            ],
            onAdded: (String _) {},
            onRemoved: (String _) {},
          ),
        ),
      );
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Mehmet'), findsOneWidget);
    });
  });

  group('SplitSummaryCard', () {
    testWidgets('should show the empty-state message when no participants',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          SplitSummaryCard(
            session: _session(),
            perPersonMinor: const <String, int>{},
          ),
        ),
      );
      expect(find.text('Add a participant first.'), findsOneWidget);
    });

    testWidgets('should render a row per participant and a total row',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          SplitSummaryCard(
            session: _session(
              participants: const <Participant>[
                Participant(id: 'p1', name: 'Ali'),
                Participant(id: 'p2', name: 'Mehmet'),
              ],
            ),
            perPersonMinor: const <String, int>{'p1': 15000, 'p2': 15000},
          ),
        ),
      );
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Mehmet'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });
  });
}
