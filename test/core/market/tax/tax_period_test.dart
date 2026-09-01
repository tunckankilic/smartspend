import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

void main() {
  group('TaxPeriodKind', () {
    test('should describe its own length in months', () {
      expect(TaxPeriodKind.monthly.monthsPerPeriod, 1);
      expect(TaxPeriodKind.quarterly.monthsPerPeriod, 3);
      expect(TaxPeriodKind.annual.monthsPerPeriod, 12);
      expect(TaxPeriodKind.oneOff.monthsPerPeriod, 0);
    });

    test('should round-trip its wire value', () {
      for (final TaxPeriodKind kind in TaxPeriodKind.values) {
        expect(TaxPeriodKind.fromWireValue(kind.wireValue), kind);
      }
    });

    test('should fall back to one-off rather than invent a recurrence', () {
      expect(TaxPeriodKind.fromWireValue('weekly'), TaxPeriodKind.oneOff);
      expect(TaxPeriodKind.fromWireValue(null), TaxPeriodKind.oneOff);
    });
  });

  group('resolveTaxPeriodKind', () {
    TaxPeriodKind? resolve(
      TaxPeriodSource source,
      TaxpayerProfile profile, {
      TaxPeriodKind fallback = TaxPeriodKind.monthly,
    }) =>
        resolveTaxPeriodKind(
          source: source,
          fallback: fallback,
          profile: profile,
        );

    test('should use the fallback for a fixed recurrence', () {
      expect(
        resolve(
          TaxPeriodSource.fixed,
          TaxpayerProfile.empty,
          fallback: TaxPeriodKind.quarterly,
        ),
        TaxPeriodKind.quarterly,
      );
    });

    test('should follow the VAT answer', () {
      expect(
        resolve(
          TaxPeriodSource.vatLiability,
          const TaxpayerProfile(vatLiability: VatLiability.monthly),
        ),
        TaxPeriodKind.monthly,
      );
      expect(
        resolve(
          TaxPeriodSource.vatLiability,
          const TaxpayerProfile(vatLiability: VatLiability.quarterly),
        ),
        TaxPeriodKind.quarterly,
      );
    });

    test('should follow the withholding answer', () {
      expect(
        resolve(
          TaxPeriodSource.withholdingLiability,
          const TaxpayerProfile(
            withholdingLiability: WithholdingLiability.quarterly,
          ),
        ),
        TaxPeriodKind.quarterly,
      );
    });

    test('should return null rather than guess the commoner option', () {
      // An unanswered question must leave a visible gap. Defaulting to
      // monthly here would put eleven invented deadlines a year in front of
      // a user who never told us they file VAT at all.
      expect(
        resolve(TaxPeriodSource.vatLiability, TaxpayerProfile.empty),
        isNull,
      );
      expect(
        resolve(
          TaxPeriodSource.withholdingLiability,
          TaxpayerProfile.empty,
        ),
        isNull,
      );
    });

    test('should return null when the taxpayer has no such liability', () {
      expect(
        resolve(
          TaxPeriodSource.vatLiability,
          const TaxpayerProfile(vatLiability: VatLiability.none),
        ),
        isNull,
      );
      expect(
        resolve(
          TaxPeriodSource.withholdingLiability,
          const TaxpayerProfile(
            withholdingLiability: WithholdingLiability.none,
          ),
        ),
        isNull,
      );
    });

    test('should leave a user-defined recurrence to the user', () {
      expect(
        resolve(TaxPeriodSource.userDefined, TaxpayerProfile.empty),
        isNull,
      );
    });
  });
}
