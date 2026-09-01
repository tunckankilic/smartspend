import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/tax_calendar_generator.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/presentation/widgets/tax_calendar_gaps_banner.dart';
import 'package:smartspend/features/taxes/presentation/widgets/tax_obligation_card.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

TaxCalendarItem item({
  TaxObligationKind kind = TaxObligationKind.kdv1,
  DateTime? declarationDue,
  DateTime? paymentDue,
  bool hasDeclarationStep = true,
  bool hasPaymentStep = true,
  bool needsDateWarning = true,
  bool isConditional = false,
  DateTime? declaredAt,
  DateTime? paidAt,
  int installmentIndex = 0,
}) =>
    TaxCalendarItem(
      id: 1,
      kind: kind,
      nameL10nKey: kind.l10nKey,
      periodKind: TaxPeriodKind.monthly,
      periodStart: DateTime.utc(2026, 8),
      periodEnd: DateTime.utc(2026, 8, 31),
      installmentIndex: installmentIndex,
      dueDateSource: TaxDueDateSource.catalog,
      amountSource: TaxAmountSource.unknown,
      hasDeclarationStep: hasDeclarationStep,
      hasPaymentStep: hasPaymentStep,
      isConditional: isConditional,
      needsDateWarning: needsDateWarning,
      isUserDefined: false,
      declarationDueDate: declarationDue,
      paymentDueDate: paymentDue,
      declaredAt: declaredAt,
      paidAt: paidAt,
    );

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  final DateTime today = DateTime.utc(2026, 9, 15);

  group('TaxObligationCard', () {
    testWidgets('shows both deadlines as separate lines',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          TaxObligationCard(
            item: item(
              declarationDue: DateTime.utc(2026, 9, 26),
              paymentDue: DateTime.utc(2026, 9, 28),
            ),
            today: today,
          ),
        ),
      );

      final AppLocalizations l = await AppLocalizations.delegate
          .load(const Locale('tr'));
      expect(find.textContaining(l.taxItemDeclarationDue), findsOneWidget);
      expect(find.textContaining(l.taxItemPaymentDue), findsOneWidget);
    });

    testWidgets('states that a missing step does not exist',
        (WidgetTester tester) async {
      // Bağ-Kur has no filing step. A blank line would read as missing data;
      // the sentence reads as the fact it is.
      await tester.pumpWidget(
        wrap(
          TaxObligationCard(
            item: item(
              kind: TaxObligationKind.bagkur,
              hasDeclarationStep: false,
              paymentDue: DateTime.utc(2026, 9, 28),
            ),
            today: today,
          ),
        ),
      );

      final AppLocalizations l = await AppLocalizations.delegate
          .load(const Locale('tr'));
      expect(find.text(l.taxItemNoDeclaration), findsOneWidget);
    });

    testWidgets('says the date is unknown rather than leaving it blank',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(TaxObligationCard(item: item(), today: today)),
      );

      final AppLocalizations l = await AppLocalizations.delegate
          .load(const Locale('tr'));
      expect(find.text(l.taxItemDateMissing), findsNWidgets(2));
    });

    testWidgets('carries the date warning on a generated item',
        (WidgetTester tester) async {
      // True for every generated item today. The card treats it as the normal
      // case rather than as an alarm.
      await tester.pumpWidget(
        wrap(
          TaxObligationCard(
            item: item(declarationDue: DateTime.utc(2026, 9, 26)),
            today: today,
          ),
        ),
      );

      expect(find.byKey(const Key('tax.card.dateWarning')), findsOneWidget);
    });

    testWidgets('drops the warning once a date is trustworthy',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          TaxObligationCard(
            item: item(
              declarationDue: DateTime.utc(2026, 9, 26),
              needsDateWarning: false,
            ),
            today: today,
          ),
        ),
      );

      expect(find.byKey(const Key('tax.card.dateWarning')), findsNothing);
    });

    testWidgets('shows overdue when an unmarked deadline has passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          TaxObligationCard(
            item: item(paymentDue: DateTime.utc(2026, 9, 10)),
            today: today,
          ),
        ),
      );

      final AppLocalizations l = await AppLocalizations.delegate
          .load(const Locale('tr'));
      expect(find.text(l.taxStateOverdue), findsOneWidget);
    });

    testWidgets('does not call a filed-but-unpaid item done',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          TaxObligationCard(
            item: item(
              declarationDue: DateTime.utc(2026, 9, 26),
              paymentDue: DateTime.utc(2026, 9, 28),
              declaredAt: DateTime.utc(2026, 9, 14),
            ),
            today: today,
          ),
        ),
      );

      final AppLocalizations l = await AppLocalizations.delegate
          .load(const Locale('tr'));
      expect(find.text(l.taxStateCompleted), findsNothing);
      expect(find.text(l.taxStateUpcoming), findsOneWidget);
    });

    testWidgets('flags a conditional obligation instead of asserting it',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          TaxObligationCard(
            item: item(kind: TaxObligationKind.kdv2, isConditional: true),
            today: today,
          ),
        ),
      );

      final AppLocalizations l = await AppLocalizations.delegate
          .load(const Locale('tr'));
      expect(find.text(l.taxItemConditional), findsOneWidget);
    });
  });

  group('TaxCalendarGapsBanner', () {
    testWidgets('names what could not be generated',
        (WidgetTester tester) async {
      // "Some items are missing" tells the user nothing they can act on.
      await tester.pumpWidget(
        wrap(
          const TaxCalendarGapsBanner(
            gaps: <TaxCalendarGap>[
              TaxCalendarGap(
                kind: TaxObligationKind.kdv1,
                reason: TaxCalendarGapReason.recurrenceUnknown,
              ),
              TaxCalendarGap(
                kind: TaxObligationKind.mphb,
                reason: TaxCalendarGapReason.applicabilityUnknown,
              ),
            ],
          ),
        ),
      );

      final AppLocalizations l = await AppLocalizations.delegate
          .load(const Locale('tr'));
      expect(find.text(l.taxObligationKdv1), findsOneWidget);
      expect(find.text(l.taxObligationMphb), findsOneWidget);
      expect(find.text(l.taxCalendarGapsTitle(2)), findsOneWidget);
      expect(
        find.byKey(const Key('tax.calendar.gaps.action')),
        findsOneWidget,
      );
    });
  });
}
