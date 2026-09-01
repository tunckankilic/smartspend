import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/due_rule.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_spec.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

void main() {
  group('TaxObligationEligibility', () {
    test('should apply to everyone when it states no condition', () {
      expect(
        TaxObligationEligibility.everyone.evaluate(TaxpayerProfile.empty),
        TaxObligationApplicability.applies,
      );
    });

    test('should be unknown while the deciding question is unanswered', () {
      const TaxObligationEligibility eligibility =
          TaxObligationEligibility(requiresEmployer: true);

      expect(
        eligibility.evaluate(TaxpayerProfile.empty),
        TaxObligationApplicability.unknown,
      );
    });

    test('should apply once the deciding question says yes', () {
      const TaxObligationEligibility eligibility =
          TaxObligationEligibility(requiresEmployer: true);

      expect(
        eligibility.evaluate(
          const TaxpayerProfile(employsStaff: TaxpayerAnswer.yes),
        ),
        TaxObligationApplicability.applies,
      );
    });

    test('should drop out once the deciding question says no', () {
      const TaxObligationEligibility eligibility =
          TaxObligationEligibility(requiresEmployer: true);

      expect(
        eligibility.evaluate(
          const TaxpayerProfile(employsStaff: TaxpayerAnswer.no),
        ),
        TaxObligationApplicability.doesNotApply,
      );
    });

    test('should let one answered "no" beat any number of unknowns', () {
      // Otherwise a user who has told us they have no staff would keep
      // seeing employer filings until they finished every other question.
      const TaxObligationEligibility eligibility = TaxObligationEligibility(
        requiresEmployer: true,
        requiresVatLiability: true,
        requiresELedger: true,
      );

      expect(
        eligibility.evaluate(
          const TaxpayerProfile(employsStaff: TaxpayerAnswer.no),
        ),
        TaxObligationApplicability.doesNotApply,
      );
    });

    test('should treat "no such liability" as a decisive no', () {
      const TaxObligationEligibility eligibility =
          TaxObligationEligibility(requiresVatLiability: true);

      expect(
        eligibility.evaluate(
          const TaxpayerProfile(vatLiability: VatLiability.none),
        ),
        TaxObligationApplicability.doesNotApply,
      );
      expect(
        eligibility.evaluate(
          const TaxpayerProfile(
            withholdingLiability: WithholdingLiability.none,
          ),
        ),
        TaxObligationApplicability.unknown,
      );
    });

    test('should gate on legal form when one is required', () {
      const TaxObligationEligibility eligibility = TaxObligationEligibility(
        legalForms: <TaxpayerLegalForm>{
          TaxpayerLegalForm.limited,
          TaxpayerLegalForm.anonim,
        },
      );

      expect(
        eligibility.evaluate(
          const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
        ),
        TaxObligationApplicability.applies,
      );
      expect(
        eligibility.evaluate(
          const TaxpayerProfile(legalForm: TaxpayerLegalForm.sahisSirketi),
        ),
        TaxObligationApplicability.doesNotApply,
      );
      expect(
        eligibility.evaluate(TaxpayerProfile.empty),
        TaxObligationApplicability.unknown,
      );
    });

    test('should require every stated condition, not just one', () {
      const TaxObligationEligibility eligibility = TaxObligationEligibility(
        requiresVehicle: true,
        requiresRealEstate: true,
      );

      expect(
        eligibility.evaluate(
          const TaxpayerProfile(
            ownsVehicle: TaxpayerAnswer.yes,
            ownsRealEstate: TaxpayerAnswer.yes,
          ),
        ),
        TaxObligationApplicability.applies,
      );
      expect(
        eligibility.evaluate(
          const TaxpayerProfile(ownsVehicle: TaxpayerAnswer.yes),
        ),
        TaxObligationApplicability.unknown,
      );
    });
  });

  group('TaxObligationSpec', () {
    const TaxObligationSpec unconfirmed = TaxObligationSpec(
      kind: TaxObligationKind.kdv1,
      periodKind: TaxPeriodKind.monthly,
      periodSource: TaxPeriodSource.vatLiability,
      eligibility: TaxObligationEligibility(requiresVatLiability: true),
      declaration: UnverifiedDueDate('filing day'),
      payment: UnverifiedDueDate('payment day'),
      sourceNote: 'to check',
    );

    test('should resolve its recurrence from the profile', () {
      expect(
        unconfirmed.resolvePeriodKind(
          const TaxpayerProfile(vatLiability: VatLiability.quarterly),
        ),
        TaxPeriodKind.quarterly,
      );
      expect(unconfirmed.resolvePeriodKind(TaxpayerProfile.empty), isNull);
    });

    test('should not count as verified while either side is unconfirmed', () {
      expect(unconfirmed.isVerified, isFalse);

      const TaxObligationSpec halfConfirmed = TaxObligationSpec(
        kind: TaxObligationKind.kdv1,
        periodKind: TaxPeriodKind.monthly,
        periodSource: TaxPeriodSource.fixed,
        eligibility: TaxObligationEligibility.everyone,
        declaration: ConfirmedDueDates(
          installments: <DueRule>[
            DueRule(monthsAfterPeriodEnd: 1, day: FixedDueDay(26)),
          ],
          source: 'a primary source, dated',
        ),
        payment: UnverifiedDueDate('payment day'),
        sourceNote: 'half done',
      );

      expect(halfConfirmed.isVerified, isFalse);
    });

    test('should count as verified when a missing side is structural', () {
      const TaxObligationSpec confirmed = TaxObligationSpec(
        kind: TaxObligationKind.babs,
        periodKind: TaxPeriodKind.monthly,
        periodSource: TaxPeriodSource.fixed,
        eligibility: TaxObligationEligibility.everyone,
        declaration: ConfirmedDueDates(
          installments: <DueRule>[
            DueRule(monthsAfterPeriodEnd: 1, day: LastDayOfMonth()),
          ],
          source: 'a primary source, dated',
        ),
        payment: NoDueDate('nothing is paid'),
        sourceNote: 'done',
      );

      expect(confirmed.isVerified, isTrue);
    });
  });
}
