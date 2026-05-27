import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/scan/data/parsers/receipt_parser.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';

/// Focused unit tests for the small helpers inside [ReceiptParser]. The
/// fixture-driven test in `receipt_parser_test.dart` covers the integrated
/// path; this file pins the building blocks so regressions are easier to
/// localize.
void main() {
  final ReceiptParser parser = ReceiptParser();

  group('parseCurrency', () {
    test('should detect TRY from ₺ symbol', () {
      expect(parser.parseCurrency(<String>['TOPLAM 25,40 ₺']), 'TRY');
    });

    test('should detect EUR from € symbol', () {
      expect(parser.parseCurrency(<String>['GESAMT 11,05 €']), 'EUR');
    });

    test('should detect GBP from £ symbol', () {
      expect(parser.parseCurrency(<String>['TOTAL £14.59']), 'GBP');
    });

    test('should fall back to TRY when ambiguous', () {
      expect(parser.parseCurrency(<String>['TOPLAM 25,40']), 'TRY');
    });
  });

  group('parseDate', () {
    test('should parse dd/MM/yyyy (TR market format)', () {
      final DateTime? d = parser.parseDate(<String>['TARİH: 15/04/2026']);
      expect(d, DateTime.utc(2026, 4, 15));
    });

    test('should parse dd.MM.yyyy (DE format)', () {
      final DateTime? d = parser.parseDate(<String>['Datum: 18.04.2026']);
      expect(d, DateTime.utc(2026, 4, 18));
    });

    test('should parse yyyy-MM-dd (ISO)', () {
      final DateTime? d = parser.parseDate(<String>['2026-04-15']);
      expect(d, DateTime.utc(2026, 4, 15));
    });

    test('should parse 2-digit year as 20xx', () {
      final DateTime? d = parser.parseDate(<String>['22-05-26']);
      expect(d, DateTime.utc(2026, 5, 22));
    });

    test('should parse Turkish month name', () {
      final DateTime? d = parser.parseDate(<String>['12 Nisan 2026']);
      expect(d, DateTime.utc(2026, 4, 12));
    });

    test('should parse German month name', () {
      final DateTime? d = parser.parseDate(<String>['25. April 2026']);
      expect(d, DateTime.utc(2026, 4, 25));
    });

    test('should return null on garbage', () {
      expect(parser.parseDate(<String>['no date here']), isNull);
    });

    test('should reject impossible day (32/13/2026)', () {
      expect(parser.parseDate(<String>['32/13/2026']), isNull);
    });
  });

  group('parseTotal', () {
    test('should pick TOPLAM line', () {
      final int? total = parser.parseTotal(<String>[
        'ARA TOPLAM 24,40',
        'KDV 1,75',
        'TOPLAM 25,40',
      ]);
      expect(total, 2540);
    });

    test('should pick GESAMT for German receipts', () {
      final int? total = parser.parseTotal(<String>[
        'Zwischensumme 11,05',
        'MwSt 0,72',
        'GESAMT 11,05',
      ]);
      expect(total, 1105);
    });

    test('should pick GENEL TOPLAM over ARA TOPLAM', () {
      final int? total = parser.parseTotal(<String>[
        'ARA TOPLAM 100,00',
        'GENEL TOPLAM 220,23',
      ]);
      expect(total, 22023);
    });

    test('should skip KDV / VAT lines even with TOPLAM nearby', () {
      final int? total = parser.parseTotal(<String>[
        'KDV TOPLAM 8,42',
        'TOPLAM 137,85',
      ]);
      expect(total, 13785);
    });

    test('should return null when no total keyword present', () {
      final int? total = parser.parseTotal(<String>[
        'ELMA 5,00',
        'EKMEK 2,50',
      ]);
      expect(total, isNull);
    });

    test('should parse thousands separator 1.234,56', () {
      final int? total = parser.parseTotal(<String>['TOPLAM 1.234,56']);
      expect(total, 123456);
    });

    test('should parse thousands separator 1,234.56 (EN)', () {
      final int? total = parser.parseTotal(<String>['TOTAL 1,234.56']);
      expect(total, 123456);
    });
  });

  group('parseTax', () {
    test('should extract KDV amount', () {
      final int? tax = parser.parseTax(<String>['KDV %18 4,75']);
      expect(tax, 475);
    });

    test('should extract MwSt amount', () {
      final int? tax = parser.parseTax(<String>['MwSt 7% 0,72']);
      expect(tax, 72);
    });

    test('should extract VAT amount', () {
      final int? tax = parser.parseTax(<String>['VAT 0.00']);
      expect(tax, 0);
    });

    test('should return null when missing', () {
      expect(parser.parseTax(<String>['EKMEK 4,50']), isNull);
    });
  });

  group('parseStoreName', () {
    test('should pick the first letter-heavy line', () {
      expect(
        parser.parseStoreName(<String>[
          'BİM BİRLEŞİK MAĞAZALAR A.Ş.',
          'ATATÜRK MAH. CUMHURİYET CAD.',
        ]),
        'BİM BİRLEŞİK MAĞAZALAR A.Ş.',
      );
    });

    test('should skip address-looking lines', () {
      expect(
        parser.parseStoreName(<String>[
          'Mah Hauptstrasse 14',
          'REWE Markt GmbH',
        ]),
        'REWE Markt GmbH',
      );
    });

    test('should skip digit-heavy lines', () {
      expect(
        parser.parseStoreName(<String>[
          '1234567890123',
          'ŞOK MARKETLER',
        ]),
        'ŞOK MARKETLER',
      );
    });
  });

  group('parseItems', () {
    test('should parse "name … price" lines', () {
      final List<ScannedItem> items = parser.parseItems(<String>[
        'SÜT 1L                          7,00',
        'EKMEK                           1,20',
      ]);
      expect(items.length, 2);
      expect(items[0].name, 'SÜT 1L');
      expect(items[0].totalPrice, 700);
      expect(items[1].name, 'EKMEK');
      expect(items[1].totalPrice, 120);
    });

    test('should merge "qty x unit_price" with previous line', () {
      final List<ScannedItem> items = parser.parseItems(<String>[
        'SÜT 1L                          7,00',
        '2 X 3,50',
      ]);
      expect(items.length, 1);
      expect(items[0].quantity, 2);
      expect(items[0].unitPrice, 350);
      expect(items[0].totalPrice, 700);
    });

    test('should skip the TOPLAM line', () {
      final List<ScannedItem> items = parser.parseItems(<String>[
        'EKMEK 4,50',
        'TOPLAM 4,50',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'EKMEK');
    });

    test('should skip barcode lines (8+ digits)', () {
      final List<ScannedItem> items = parser.parseItems(<String>[
        '8690123456789',
        'EKMEK 4,50',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'EKMEK');
    });
  });
}
