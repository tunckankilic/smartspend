import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/tax_obligation_record.dart';

void main() {
  group('TaxAmountSource', () {
    test('should have no value meaning "the app worked it out"', () {
      // 🚨 SmartSpend does not calculate tax: no line-item VAT breakdown
      // before 1.6.0, no knowledge of the user's deductions, no licence. A
      // number this app produced would be read as an amount to pay.
      expect(
        TaxAmountSource.values.map((TaxAmountSource s) => s.name),
        <String>['accountant', 'user', 'unknown'],
      );
      expect(
        TaxAmountSource.values.map((TaxAmountSource s) => s.wireValue),
        isNot(contains('computed')),
      );
    });

    test('should read a forbidden value back as unknown', () {
      // Even a row written by a build that broke the rule cannot present a
      // calculated figure as authoritative.
      expect(
        TaxAmountSource.fromWireValue('computed'),
        TaxAmountSource.unknown,
      );
      expect(TaxAmountSource.fromWireValue(null), TaxAmountSource.unknown);
    });
  });

  group('TaxDueDateSource', () {
    test('should round-trip and default to the catalog', () {
      for (final TaxDueDateSource source in TaxDueDateSource.values) {
        expect(TaxDueDateSource.fromWireValue(source.wireValue), source);
      }
      expect(
        TaxDueDateSource.fromWireValue('sirküler'),
        TaxDueDateSource.catalog,
      );
    });
  });

  group('deriveTaxObligationState', () {
    TaxObligationState state({
      required DateTime today,
      bool hasDeclarationStep = true,
      bool hasPaymentStep = true,
      DateTime? declarationDue,
      DateTime? paymentDue,
      DateTime? declaredAt,
      DateTime? paidAt,
      DateTime? dismissedAt,
    }) =>
        deriveTaxObligationState(
          today: today,
          hasDeclarationStep: hasDeclarationStep,
          hasPaymentStep: hasPaymentStep,
          declarationDueDate: declarationDue,
          paymentDueDate: paymentDue,
          declaredAt: declaredAt,
          paidAt: paidAt,
          dismissedAt: dismissedAt,
        );

    test('should be upcoming before the earliest outstanding deadline', () {
      expect(
        state(
          today: DateTime.utc(2026, 9, 20),
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
        ),
        TaxObligationState.upcoming,
      );
    });

    test('should be due today on the day itself', () {
      expect(
        state(
          today: DateTime.utc(2026, 9, 26, 23, 59),
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
        ),
        TaxObligationState.dueToday,
      );
    });

    test('should be overdue once an unmarked deadline has passed', () {
      expect(
        state(
          today: DateTime.utc(2026, 9, 27),
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
        ),
        TaxObligationState.overdue,
      );
    });

    test('should stop counting a step once it is marked', () {
      // Filed on time, payment still ahead: not overdue.
      expect(
        state(
          today: DateTime.utc(2026, 9, 27),
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
          declaredAt: DateTime.utc(2026, 9, 25),
        ),
        TaxObligationState.upcoming,
      );
    });

    test('should not treat filing as paying', () {
      expect(
        state(
          today: DateTime.utc(2026, 9, 20),
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
          declaredAt: DateTime.utc(2026, 9, 19),
        ),
        isNot(TaxObligationState.completed),
      );
    });

    test('should complete when every step that exists is marked', () {
      expect(
        state(
          today: DateTime.utc(2026, 9, 29),
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
          declaredAt: DateTime.utc(2026, 9, 25),
          paidAt: DateTime.utc(2026, 9, 28),
        ),
        TaxObligationState.completed,
      );
    });

    test('should complete an obligation that has no filing step', () {
      // Bağ-Kur is assessed, never declared: declaredAt stays null forever,
      // and without the catalog telling us the step does not exist this could
      // never be finished.
      expect(
        state(
          today: DateTime.utc(2026, 9, 29),
          hasDeclarationStep: false,
          paymentDue: DateTime.utc(2026, 9, 28),
          paidAt: DateTime.utc(2026, 9, 28),
        ),
        TaxObligationState.completed,
      );
    });

    test('should complete an obligation that is never paid', () {
      // Ba/Bs and the e-ledger berat: filed, never paid.
      expect(
        state(
          today: DateTime.utc(2026, 9, 29),
          hasPaymentStep: false,
          declarationDue: DateTime.utc(2026, 9, 26),
          declaredAt: DateTime.utc(2026, 9, 26),
        ),
        TaxObligationState.completed,
      );
    });

    test('should say undated rather than upcoming with no deadline', () {
      // Today's normal case: the rule is unverified. "Upcoming" would imply
      // we know the date has not passed.
      expect(
        state(today: DateTime.utc(2026, 9, 20)),
        TaxObligationState.undated,
      );
    });

    test('should let a dismissal outrank everything', () {
      expect(
        state(
          today: DateTime.utc(2027),
          declarationDue: DateTime.utc(2026, 9, 26),
          dismissedAt: DateTime.utc(2026, 9),
        ),
        TaxObligationState.dismissed,
      );
    });

    test('should read only from the arguments it is given', () {
      // The reason this is a function of `today` rather than of the clock: a
      // device whose date is wrong shows itself a wrong badge and nothing
      // else. There is no column for it, so nothing propagates.
      final TaxObligationState onTime = state(
        today: DateTime.utc(2026, 9, 20),
        declarationDue: DateTime.utc(2026, 9, 26),
      );
      final TaxObligationState brokenClock = state(
        today: DateTime.utc(2031),
        declarationDue: DateTime.utc(2026, 9, 26),
      );

      expect(onTime, TaxObligationState.upcoming);
      expect(brokenClock, TaxObligationState.overdue);
    });
  });
}
