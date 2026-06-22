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

    test(r'should not read a bare $ as USD (ML Kit misreads TR * marker)', () {
      // ML Kit routinely transcribes the TR receipt marker '*' as '$'.
      expect(parser.parseCurrency(<String>[r'K.KARTI: $670,41']), 'TRY');
    });

    test('should detect USD only from the ISO code', () {
      expect(parser.parseCurrency(<String>['TOTAL 5.00 USD']), 'USD');
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

    test('should prefer ÖDENECEK TUTAR over MAL/HİZMET subtotal', () {
      // A101 e-Arşiv: the goods subtotal matches TOPLAM, but the payable
      // grand total is "Ödenecek Tutar" — that one must win.
      final int? total = parser.parseTotal(<String>[
        'MAL/HİZMET TOPLAM TUTARI 68,81',
        'ÖDENECEK TUTAR 69,50',
      ]);
      expect(total, 6950);
    });

    test('should read "Ödenecek KDV Dahil Tutar" despite the KDV word', () {
      // BİM e-Arşiv: the only grand-total line also says "KDV Dahil"; the
      // payable keyword overrides the KDV negative filter (else total = 0).
      final int? total = parser.parseTotal(<String>[
        'TOPLAM KDV 2,70',
        'Ödenecek KDV Dahil Tutar 257,00',
      ]);
      expect(total, 25700);
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

    test('should reject lines whose trailing number has no cents tail', () {
      // Addresses, phone numbers, receipt/tax IDs end in a bare integer —
      // never a real item price.
      final List<ScannedItem> items = parser.parseItems(<String>[
        'ATATÜRK MAH. CUMHURİYET CAD. NO:42',
        'TEL: 0212 555 12 34',
        'EKMEK 4,50',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'EKMEK');
    });

    test('should skip payment / change lines that carry an amount', () {
      final List<ScannedItem> items = parser.parseItems(<String>[
        'EKMEK 4,50',
        'NAKİT 70,00',
        'PARA ÜSTÜ 5,63',
        'KART 64,37',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'EKMEK');
    });

    test('should keep two-letter product names like SU', () {
      final List<ScannedItem> items = parser.parseItems(<String>[
        'SU 5L 12,00',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'SU 5L');
      expect(items[0].totalPrice, 1200);
    });

    test('should read qty + unit from an inline "qty x unit total" line', () {
      // "SÜT 2 X 3,50  7,00" → name SÜT, qty 2, unit 350, total 700.
      final List<ScannedItem> items = parser.parseItems(<String>[
        'SÜT 1L           2 X 3,50    7,00',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'SÜT 1L');
      expect(items[0].quantity, 2);
      expect(items[0].unitPrice, 350);
      expect(items[0].totalPrice, 700);
    });

    test('should drop a standalone "N AD X price" qty sub-line with no '
        'preceding item', () {
      // TR e-Arşiv receipts print a unit-count line ("2 AD X 37,50") under a
      // product. When column split strips the product, the bare qty line must
      // never become an item named "2 ad X" (the real-device BİM regression).
      final List<ScannedItem> items = parser.parseItems(<String>[
        '2 ad X 37,50',
        '2 ad X 49,50',
      ]);
      expect(items, isEmpty);
    });

    test('should apply a "N AD X price" sub-line to the previous item', () {
      final List<ScannedItem> items = parser.parseItems(<String>[
        'KAYA TUZU 1.5 KG 19,50',
        '2 ad X 37,50',
      ]);
      expect(items.length, 1);
      expect(items.single.name, 'KAYA TUZU 1.5 KG');
      expect(items.single.quantity, 2);
      expect(items.single.unitPrice, 3750);
    });

    test('should skip the "Ödenecek Tutar" payable line as an item', () {
      // A101 e-Arşiv leaked "ÖDENECEK TUTAR" in as a product before this.
      final List<ScannedItem> items = parser.parseItems(<String>[
        'EKMEK 4,50',
        'ÖDENECEK TUTAR 69,50',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'EKMEK');
    });

    test('should skip Turkish-suffixed card lines like "K.KARTI"', () {
      // "\bKART\b" missed the inflected "KARTI"; the payment filter lists it.
      final List<ScannedItem> items = parser.parseItems(<String>[
        'EKMEK 4,50',
        'K.KARTI: 670,41',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'EKMEK');
    });

    test('should skip card POS tender lines like "TEK POS"', () {
      // ŞOK prints the masked card + "TEK POS" as the tender line; it must
      // not become a product.
      final List<ScannedItem> items = parser.parseItems(<String>[
        'EKMEK 4,50',
        '#494314*****6204 TEK POS 145,00',
      ]);
      expect(items.length, 1);
      expect(items[0].name, 'EKMEK');
    });
  });
}
