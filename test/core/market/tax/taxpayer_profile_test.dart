import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/core/services/telemetry_service.dart';

void main() {
  group('TaxpayerProfile', () {
    test('should default every dimension to unknown', () {
      const TaxpayerProfile profile = TaxpayerProfile.empty;

      expect(profile.legalForm, TaxpayerLegalForm.unspecified);
      expect(profile.vatLiability, VatLiability.unknown);
      expect(profile.withholdingLiability, WithholdingLiability.unknown);
      expect(profile.employsStaff, TaxpayerAnswer.unknown);
      expect(profile.bagkurInsured, TaxpayerAnswer.unknown);
      expect(profile.usesELedger, TaxpayerAnswer.unknown);
      expect(profile.ownsVehicle, TaxpayerAnswer.unknown);
      expect(profile.ownsRealEstate, TaxpayerAnswer.unknown);
      expect(profile.isComplete, isFalse);
      expect(profile.answeredCount, 0);
    });

    test('should count answers as the wizard fills them in', () {
      const TaxpayerProfile profile = TaxpayerProfile(
        legalForm: TaxpayerLegalForm.limited,
        vatLiability: VatLiability.monthly,
      );

      expect(profile.answeredCount, 2);
      expect(profile.isComplete, isFalse);
    });

    test('should be complete only when all eight questions are answered', () {
      const TaxpayerProfile profile = TaxpayerProfile(
        legalForm: TaxpayerLegalForm.limited,
        vatLiability: VatLiability.monthly,
        withholdingLiability: WithholdingLiability.monthly,
        employsStaff: TaxpayerAnswer.yes,
        bagkurInsured: TaxpayerAnswer.no,
        usesELedger: TaxpayerAnswer.no,
        ownsVehicle: TaxpayerAnswer.no,
        ownsRealEstate: TaxpayerAnswer.no,
      );

      expect(profile.isComplete, isTrue);
      expect(profile.answeredCount, TaxpayerProfile.questionCount);
      expect(TaxpayerProfile.questionCount, 8);
    });

    test('should compare by its eight answers', () {
      // Same answers means same calendar, so a caller can skip regenerating
      // when a wizard round trip changed nothing.
      expect(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
      );
      expect(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
        isNot(const TaxpayerProfile(legalForm: TaxpayerLegalForm.anonim)),
      );
      expect(TaxpayerProfile.empty.copyWith(), TaxpayerProfile.empty);
    });

    test('should replace only the answers copyWith is given', () {
      const TaxpayerProfile profile = TaxpayerProfile(
        legalForm: TaxpayerLegalForm.anonim,
        ownsVehicle: TaxpayerAnswer.yes,
      );

      final TaxpayerProfile updated =
          profile.copyWith(ownsVehicle: TaxpayerAnswer.no);

      expect(updated.legalForm, TaxpayerLegalForm.anonim);
      expect(updated.ownsVehicle, TaxpayerAnswer.no);
    });
  });

  group('legal form / telemetry bucket correspondence', () {
    test('should map every legal form to a distinct telemetry dimension', () {
      final Set<TelemetryDimension> dimensions = TaxpayerLegalForm.values
          .map((TaxpayerLegalForm form) => form.telemetryDimension)
          .toSet();

      expect(dimensions.length, TaxpayerLegalForm.values.length);
    });

    test('should leave no telemetry bucket unreachable from the wizard', () {
      // D-2 is answered by the distribution of this dimension. A bucket the
      // wizard can never produce would show up as a permanent zero and be
      // read as a finding about the market rather than a gap in the form.
      final Set<TelemetryDimension> reachable = TaxpayerLegalForm.values
          .map((TaxpayerLegalForm form) => form.telemetryDimension)
          .toSet();

      expect(reachable, TelemetryDimension.values.toSet());
    });

    test('should share the wire value with the telemetry bucket', () {
      for (final TaxpayerLegalForm form in TaxpayerLegalForm.values) {
        expect(form.wireValue, form.telemetryDimension.value);
      }
    });
  });

  group('wire values', () {
    test('should round-trip every enum', () {
      for (final TaxpayerAnswer answer in TaxpayerAnswer.values) {
        expect(TaxpayerAnswer.fromWireValue(answer.wireValue), answer);
      }
      for (final TaxpayerLegalForm form in TaxpayerLegalForm.values) {
        expect(TaxpayerLegalForm.fromWireValue(form.wireValue), form);
      }
      for (final VatLiability liability in VatLiability.values) {
        expect(VatLiability.fromWireValue(liability.wireValue), liability);
      }
      for (final WithholdingLiability liability
          in WithholdingLiability.values) {
        expect(
          WithholdingLiability.fromWireValue(liability.wireValue),
          liability,
        );
      }
    });

    test('should read an unknown value from a newer client as unknown', () {
      expect(TaxpayerAnswer.fromWireValue('maybe'), TaxpayerAnswer.unknown);
      expect(TaxpayerAnswer.fromWireValue(null), TaxpayerAnswer.unknown);
      expect(
        TaxpayerLegalForm.fromWireValue('kooperatif'),
        TaxpayerLegalForm.unspecified,
      );
      expect(VatLiability.fromWireValue('yearly'), VatLiability.unknown);
      expect(
        WithholdingLiability.fromWireValue('yearly'),
        WithholdingLiability.unknown,
      );
    });
  });
}
