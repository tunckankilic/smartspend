import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/market/country_profile.dart';
import 'package:smartspend/core/market/document_type.dart';
import 'package:smartspend/core/market/tr_profile.dart';

void main() {
  group('TrProfile', () {
    const CountryProfile profile = TrProfile();

    test('should describe the Turkish market', () {
      expect(profile.countryCode, 'TR');
      expect(profile.currencyCode, 'TRY');
      expect(profile.defaultLanguageCode, 'tr');
      expect(profile.defaultVatRateBp, 2000);
    });

    test('should expose the KDV rates as ascending basis points', () {
      expect(profile.vatRatesBp, <int>[0, 100, 1000, 2000]);
      final List<int> sorted = List<int>.of(profile.vatRatesBp)..sort();
      expect(profile.vatRatesBp, sorted);
    });

    test('should list the Turkish document types in picker order', () {
      expect(profile.documentTypes, <DocumentType>[
        DocumentType.fis,
        DocumentType.eArsivFatura,
        DocumentType.eFatura,
        DocumentType.giderPusulasi,
        DocumentType.other,
      ]);
      expect(profile.isDocumentTypeSupported(DocumentType.eFatura), isTrue);
    });

    test('should recognise legal rates only', () {
      expect(profile.isVatRateSupported(2000), isTrue);
      expect(profile.isVatRateSupported(0), isTrue);
      expect(profile.isVatRateSupported(1800), isFalse);
      expect(profile.isVatRateSupported(20), isFalse);
    });

    group('nearestVatRateBp', () {
      test('should return an exact rate unchanged', () {
        expect(profile.nearestVatRateBp(1000), 1000);
      });

      test('should snap a noisy OCR rate to the closest legal rate', () {
        expect(profile.nearestVatRateBp(1900), 2000);
        expect(profile.nearestVatRateBp(120), 100);
        expect(profile.nearestVatRateBp(40), 0);
      });

      test('should break a tie toward the lower rate', () {
        // Exactly between 100 and 1000.
        expect(profile.nearestVatRateBp(550), 100);
      });

      test('should clamp values outside the legal range', () {
        expect(profile.nearestVatRateBp(9999), 2000);
        expect(profile.nearestVatRateBp(-500), 0);
      });
    });

    group('VAT arithmetic', () {
      test('should compute VAT on a net base', () {
        expect(profile.vatOnBase(10000, 2000), 2000);
        expect(profile.vatOnBase(10000, 1000), 1000);
        expect(profile.vatOnBase(10000, 0), 0);
      });

      test('should round half away from zero on a net base', () {
        // 1234 kuruş × 1% = 12.34 → 12
        expect(profile.vatOnBase(1234, 100), 12);
        // 1250 kuruş × 1% = 12.50 → 13
        expect(profile.vatOnBase(1250, 100), 13);
      });

      test('should extract VAT contained in a gross amount', () {
        // 120.00 TRY gross at 20% contains 20.00 TRY VAT.
        expect(profile.vatFromGross(12000, 2000), 2000);
        // 110.00 TRY gross at 10% contains 10.00 TRY VAT.
        expect(profile.vatFromGross(11000, 1000), 1000);
        expect(profile.vatFromGross(9999, 0), 0);
      });

      test('should keep gross extraction consistent with base computation',
          () {
        const int base = 4567;
        const int rate = 2000;
        final int vat = profile.vatOnBase(base, rate);
        expect(profile.vatFromGross(base + vat, rate), vat);
      });

      test('should handle negative amounts (refund lines) symmetrically', () {
        expect(profile.vatOnBase(-10000, 2000), -2000);
        expect(profile.vatFromGross(-12000, 2000), -2000);
      });
    });
  });

  group('DocumentType', () {
    test('should round-trip every wire value', () {
      for (final DocumentType type in DocumentType.values) {
        expect(DocumentType.fromWireValue(type.wireValue), type);
      }
    });

    test('should decode an unknown or null value as other', () {
      expect(DocumentType.fromWireValue('kleinbetragsrechnung'),
          DocumentType.other);
      expect(DocumentType.fromWireValue(null), DocumentType.other);
    });

    test('should keep wire values unique and stable', () {
      expect(
        DocumentType.values.map((DocumentType t) => t.wireValue).toSet(),
        hasLength(DocumentType.values.length),
      );
      expect(DocumentType.fis.wireValue, 'fis');
      expect(DocumentType.eArsivFatura.wireValue, 'eArsivFatura');
      expect(DocumentType.giderPusulasi.wireValue, 'giderPusulasi');
    });
  });
}
