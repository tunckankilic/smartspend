// All regex literals are kept as raw strings even when they don't contain
// escape sequences — it's the project convention and signals "this is a
// pattern, not a normal string."
// ignore_for_file: unnecessary_raw_strings

import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';

/// Parses raw OCR text into a structured [ScannedReceipt].
///
/// Targets TR / DE / EN-UK receipt formats:
/// - **TR markets** (BİM, A101, Migros, ŞOK, CarrefourSA): "TOPLAM" + KDV
/// - **TR restaurants:** "GENEL TOPLAM", service charge possible
/// - **DE** (Aldi, Lidl, REWE, Edeka): "GESAMT" / "SUMME" + MwSt
/// - **UK** (Tesco, Sainsbury's): "TOTAL" + VAT
///
/// Money is always returned in the smallest unit of the inferred currency:
/// kuruş for TRY, cent for EUR/GBP/USD. Strings like `12,50` (TR/DE) and
/// `12.50` (EN) both parse to `1250`.
class ReceiptParser {
  ReceiptParser();

  // ---------------------------------------------------------------------
  // Public entry point
  // ---------------------------------------------------------------------

  ScannedReceipt parse(OCRResult ocr, {required String imagePath}) {
    final List<String> lines = _normalizeLines(ocr.rawText);
    final String currency = parseCurrency(lines);

    return ScannedReceipt(
      imagePath: imagePath,
      storeName: parseStoreName(lines),
      date: parseDate(lines),
      items: parseItems(lines),
      total: parseTotal(lines) ?? 0,
      currency: currency,
      rawText: ocr.rawText,
      confidenceScore: ocr.confidence,
    );
  }

  List<String> _normalizeLines(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // Store name — first non-numeric, non-address line on the receipt
  // ---------------------------------------------------------------------

  static final RegExp _hasLetters = RegExp(
    r'[A-Za-zÇĞİÖŞÜçğıöşüÄÖÜäöüß]{3,}',
  );
  static final RegExp _looksLikeAddress = RegExp(
    r'\b(Mah|Mahalle|Cad|Cd|Sok|Sk|No|str|strasse|straße|street|rd|road)\b',
    caseSensitive: false,
  );

  String? parseStoreName(List<String> lines) {
    for (final String line in lines.take(4)) {
      if (!_hasLetters.hasMatch(line)) continue;
      if (_looksLikeAddress.hasMatch(line)) continue;
      if (_isMostlyDigits(line)) continue;
      // Squash repeated whitespace; preserve original case.
      return line.replaceAll(RegExp(r'\s+'), ' ');
    }
    return null;
  }

  bool _isMostlyDigits(String s) {
    final int digits = s.runes.where(_isDigit).length;
    return digits / s.length > 0.6;
  }

  bool _isDigit(int r) => r >= 0x30 && r <= 0x39;

  // ---------------------------------------------------------------------
  // Date — numeric formats + TR/DE/EN month names
  // ---------------------------------------------------------------------

  // Numeric: 15/04/2026, 15.04.26, 2026-04-15
  static final RegExp _numericDate = RegExp(
    r'(\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b)|'
    r'(\b\d{4}-\d{1,2}-\d{1,2}\b)',
  );

  // Spelled month: "15 Nisan 2026", "15. April 2026", "15 April 2026"
  static final RegExp _spelledDate = RegExp(
    r'\b(\d{1,2})\.?\s+'
    r'(ocak|şubat|subat|mart|nisan|mayıs|mayis|haziran|temmuz|ağustos|agustos|'
    r'eylül|eylul|ekim|kasım|kasim|aralık|aralik|'
    r'januar|februar|märz|marz|april|mai|juni|juli|august|september|oktober|'
    r'november|dezember|'
    r'january|february|march|april|may|june|july|august|september|october|'
    r'november|december)\s+'
    r'(\d{2,4})\b',
    caseSensitive: false,
  );

  static const Map<String, int> _monthLookup = <String, int>{
    'ocak': 1, 'şubat': 2, 'subat': 2, 'mart': 3, 'nisan': 4,
    'mayıs': 5, 'mayis': 5, 'haziran': 6, 'temmuz': 7,
    'ağustos': 8, 'agustos': 8, 'eylül': 9, 'eylul': 9,
    'ekim': 10, 'kasım': 11, 'kasim': 11, 'aralık': 12, 'aralik': 12,
    'januar': 1, 'februar': 2, 'märz': 3, 'marz': 3, 'april': 4,
    'mai': 5, 'juni': 6, 'juli': 7, 'august': 8, 'september': 9,
    'oktober': 10, 'november': 11, 'dezember': 12,
    'january': 1, 'february': 2, 'march': 3, 'may': 5, 'june': 6,
    'july': 7, 'october': 10, 'december': 12,
  };

  DateTime? parseDate(List<String> lines) {
    final String joined = lines.join(' ');

    final RegExpMatch? numeric = _numericDate.firstMatch(joined);
    if (numeric != null) {
      final DateTime? parsed = _parseNumericDate(numeric.group(0)!);
      if (parsed != null) return parsed;
    }

    final RegExpMatch? spelled = _spelledDate.firstMatch(joined);
    if (spelled != null) {
      final int day = int.parse(spelled.group(1)!);
      final int? month = _monthLookup[spelled.group(2)!.toLowerCase()];
      final int year = _normalizeYear(int.parse(spelled.group(3)!));
      if (month != null && _isValidDay(day, month, year)) {
        return DateTime.utc(year, month, day);
      }
    }

    return null;
  }

  DateTime? _parseNumericDate(String token) {
    // yyyy-mm-dd
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(token)) {
      final List<String> parts = token.split('-');
      final int y = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
      final int d = int.parse(parts[2]);
      return _isValidDay(d, m, y) ? DateTime.utc(y, m, d) : null;
    }
    // dd/mm/yyyy or dd.mm.yyyy or dd-mm-yyyy
    final List<String> parts = token.split(RegExp(r'[./-]'));
    if (parts.length != 3) return null;
    final int d = int.parse(parts[0]);
    final int m = int.parse(parts[1]);
    final int y = _normalizeYear(int.parse(parts[2]));
    return _isValidDay(d, m, y) ? DateTime.utc(y, m, d) : null;
  }

  int _normalizeYear(int y) => y < 100 ? 2000 + y : y;

  bool _isValidDay(int d, int m, int y) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return false;
    final DateTime probe = DateTime.utc(y, m, d);
    return probe.month == m && probe.day == d;
  }

  // ---------------------------------------------------------------------
  // Currency — symbol or ISO code; defaults to TRY when ambiguous
  // ---------------------------------------------------------------------

  String parseCurrency(List<String> lines) {
    final String joined = lines.join(' ').toUpperCase();
    if (joined.contains('₺') ||
        joined.contains('TRY') ||
        joined.contains('TL')) {
      return 'TRY';
    }
    if (joined.contains('€') || joined.contains('EUR')) return 'EUR';
    if (joined.contains('£') || joined.contains('GBP')) return 'GBP';
    if (joined.contains(r'$') || joined.contains('USD')) return 'USD';
    return 'TRY';
  }

  // ---------------------------------------------------------------------
  // Total — keyword-anchored; matches the largest plausible amount
  // ---------------------------------------------------------------------

  static final RegExp _totalKeyword = RegExp(
    r'(GENEL\s*TOPLAM|TOPLAM|TOTAL|GESAMTBETRAG|GESAMT|SUMME|'
    r'ZU\s*ZAHLEN|ZAHLBETRAG|BETRAG|SUM)',
    caseSensitive: false,
  );

  /// Lines that look like totals but aren't (subtotals, change, tax).
  static final RegExp _totalNegativeKeyword = RegExp(
    r'(KDV|VAT|MWST|MWSTR|ARA\s*TOPLAM|SUBTOTAL|ZWISCHENSUMME|'
    r'NACHLASS|ÄNDERUNG|CHANGE|PARA\s*ÜSTÜ)',
    caseSensitive: false,
  );

  int? parseTotal(List<String> lines) {
    int? best;
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (!_totalKeyword.hasMatch(line)) continue;
      if (_totalNegativeKeyword.hasMatch(line)) continue;

      // Amount on the same line, or the next non-empty line.
      int? amount = _extractLastAmount(line);
      if (amount == null && i + 1 < lines.length) {
        amount = _extractLastAmount(lines[i + 1]);
      }
      if (amount == null) continue;
      if (best == null || amount > best) best = amount;
    }
    return best;
  }

  // ---------------------------------------------------------------------
  // Tax — KDV / VAT / MwSt
  // ---------------------------------------------------------------------

  static final RegExp _taxKeyword = RegExp(
    r'(KDV|VAT|MWST|MEHRWERTSTEUER)',
    caseSensitive: false,
  );

  int? parseTax(List<String> lines) {
    for (final String line in lines) {
      if (!_taxKeyword.hasMatch(line)) continue;
      final int? amount = _extractLastAmount(line);
      if (amount != null) return amount;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Items — line-by-line "name … price" + "qty x unit_price" forms
  // ---------------------------------------------------------------------

  // Trailing amount: 12,50 / 12.50 / 1.234,56 / 1,234.56 — currency
  // suffix (€ £ $ ₺) and trailing punctuation are tolerated.
  static final RegExp _trailingAmount = RegExp(
    r'([\d.,]+)\s*[€£$₺]?\s*[.,]?\s*$',
  );

  /// Strips currency symbols + trailing punctuation that confuse the
  /// item-line tokenizer.
  String _stripCurrencyTail(String line) {
    return line.replaceAll(RegExp(r'[€£$₺]'), '').trimRight();
  }

  // Quantity prefix: "2 x 3,50" / "2× 3.50" / "0,345 KG x 24,90"
  static final RegExp _qtyTimesPrice = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:KG|G|L|ML|ADET)?\s*[x×*]\s*([\d.,]+)',
    caseSensitive: false,
  );

  List<ScannedItem> parseItems(List<String> lines) {
    final List<ScannedItem> items = <ScannedItem>[];
    for (int i = 0; i < lines.length; i++) {
      final String line = _stripCurrencyTail(lines[i]);
      if (_isStructuralLine(line)) continue;

      // Pattern A: qty × price on its own line modifies the previous item.
      final RegExpMatch? qtyMatch = _qtyTimesPrice.firstMatch(line);
      if (qtyMatch != null && items.isNotEmpty) {
        final num qty = _parseNumeric(qtyMatch.group(1)!);
        final int unitPrice = _parseAmount(qtyMatch.group(2)!) ?? 0;
        final ScannedItem prev = items.removeLast();
        items.add(
          prev.copyWith(
            quantity: qty,
            unitPrice: unitPrice,
            totalPrice: (qty * unitPrice).round(),
          ),
        );
        continue;
      }

      // Pattern B: "name … 12,50" — most TR / DE / UK markets.
      final RegExpMatch? trailing = _trailingAmount.firstMatch(line);
      if (trailing == null) continue;
      final int? amount = _parseAmount(trailing.group(1)!);
      if (amount == null) continue;
      final String name = line
          .substring(0, trailing.start)
          .trim()
          .replaceAll(RegExp(r'[*x×•·]+$'), '')
          .trim();
      if (name.isEmpty || !_hasLetters.hasMatch(name)) continue;
      if (_totalKeyword.hasMatch(name) ||
          _totalNegativeKeyword.hasMatch(name) ||
          _taxKeyword.hasMatch(name)) {
        continue;
      }

      items.add(
        ScannedItem(
          name: name,
          quantity: 1,
          unitPrice: amount,
          totalPrice: amount,
        ),
      );
    }
    return items;
  }

  /// Lines we never treat as items: barcodes, register footer, etc.
  bool _isStructuralLine(String line) {
    if (line.length < 3) return true;
    if (RegExp(r'^[*=\-_]{3,}$').hasMatch(line)) return true;
    if (RegExp(r'^\d{8,}$').hasMatch(line)) return true; // barcode
    if (RegExp(r'^TARİH|^TARIH|^SAAT|^DATUM|^ZEIT|^FİŞ|^FIS|^BON|^BELEG|'
            r'^KASA|^KASIYER|^KASSE|^SUBE|^ŞUBE|^STORE',
        caseSensitive: false).hasMatch(line)) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Amount parsing: handles both 1.234,56 and 1,234.56 — last symbol wins
  // ---------------------------------------------------------------------

  /// Returns the amount in the smallest currency unit (kuruş / cent), or
  /// `null` if the token can't be parsed cleanly.
  int? _parseAmount(String token) {
    final String cleaned = token.replaceAll(RegExp(r'[^\d.,]'), '');
    if (cleaned.isEmpty) return null;

    final int lastDot = cleaned.lastIndexOf('.');
    final int lastComma = cleaned.lastIndexOf(',');
    String normalized;

    if (lastDot == -1 && lastComma == -1) {
      // Integer — pad cents.
      normalized = '$cleaned.00';
    } else if (lastDot > lastComma) {
      // Dot is decimal separator (EN format). Strip thousands commas.
      normalized = cleaned.replaceAll(',', '');
    } else {
      // Comma is decimal separator (TR/DE format). Strip thousands dots,
      // then swap the decimal comma for a dot.
      normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
    }

    final double? value = double.tryParse(normalized);
    if (value == null) return null;
    // Money is stored in cents — round to avoid floating-point ghosts.
    return (value * 100).round();
  }

  num _parseNumeric(String token) {
    final String cleaned = token.replaceAll(',', '.');
    return num.tryParse(cleaned) ?? 1;
  }

  int? _extractLastAmount(String line) {
    // Match the rightmost amount on the line — totals are usually on the
    // right edge of receipts.
    final Iterable<RegExpMatch> matches = RegExp(
      r'\d[\d.,]*',
    ).allMatches(line);
    if (matches.isEmpty) return null;
    return _parseAmount(matches.last.group(0)!);
  }
}
