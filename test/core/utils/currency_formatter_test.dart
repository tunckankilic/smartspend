import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';

void main() {
  group('formatMinor', () {
    test('should render TRY in Turkish locale with the lira glyph', () {
      final String out = formatMinor(123456, 'TRY', locale: 'tr');
      // Turkish locale uses non-breaking-space and comma decimal — we
      // assert on stable substrings rather than the exact glyph layout.
      expect(out, contains('1.234,56'));
      expect(out, contains('₺'));
    });

    test('should render EUR in German locale', () {
      final String out = formatMinor(123456, 'EUR', locale: 'de');
      expect(out, contains('1.234,56'));
      expect(out, contains('€'));
    });

    test('should render USD in US English locale', () {
      final String out = formatMinor(123456, 'USD', locale: 'en_US');
      expect(out, contains('1,234.56'));
      expect(out, contains(r'$'));
    });

    test('should render an unknown currency with the raw code as symbol',
        () {
      final String out = formatMinor(500, 'AED', locale: 'en_US');
      expect(out, contains('5.00'));
      expect(out, contains('AED'));
    });
  });

  group('parseMinorInput', () {
    test('should parse comma decimal as minor units', () {
      expect(parseMinorInput('12,50'), 1250);
    });

    test('should parse dot decimal as minor units', () {
      expect(parseMinorInput('12.50'), 1250);
    });

    test('should handle whole numbers', () {
      expect(parseMinorInput('42'), 4200);
    });

    test('should round to the nearest minor unit', () {
      expect(parseMinorInput('12.345'), 1235);
    });

    test('should return null for empty input', () {
      expect(parseMinorInput(''), isNull);
      expect(parseMinorInput('   '), isNull);
    });

    test('should return null for non-numeric input', () {
      expect(parseMinorInput('abc'), isNull);
    });

    test('should reject Infinity / NaN', () {
      expect(parseMinorInput('Infinity'), isNull);
      expect(parseMinorInput('NaN'), isNull);
    });
  });

  group('currencySymbol', () {
    test('should map known codes to glyphs', () {
      expect(currencySymbol('TRY'), '₺');
      expect(currencySymbol('EUR'), '€');
      expect(currencySymbol('GBP'), '£');
      expect(currencySymbol('USD'), r'$');
    });

    test('should fall back to the raw code for unknown currencies', () {
      expect(currencySymbol('JPY'), 'JPY');
    });
  });
}
