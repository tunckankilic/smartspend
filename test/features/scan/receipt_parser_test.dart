import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';
import 'package:smartspend/features/scan/data/parsers/receipt_parser.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';

/// Drives [ReceiptParser] against every fixture under
/// `test/fixtures/scan/receipts/`. Each receipt is two files:
///
/// - `<slug>.txt`  — raw OCR text (what an engine would emit)
/// - `<slug>.json` — expected parsed fields. Per-field schema:
///     storeName : string | null
///     date      : "YYYY-MM-DD" | null
///     currency  : "TRY" | "EUR" | "GBP" | "USD"
///     total     : int (smallest currency unit)
///     tax       : int | null
///     minItems  : int (parser must extract at least this many items)
///
/// Sprint 2.2 ships 12 fixtures — 5 TR markets, 1 TR restaurant, 1 cafe,
/// 2 DE, 1 UK, 2 edge cases (missing total, missing date).
void main() {
  final Directory fixturesDir = Directory('test/fixtures/scan/receipts');
  final ReceiptParser parser = ReceiptParser();

  final List<File> txtFiles = fixturesDir
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.txt'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  test('fixture directory should contain at least 10 receipts', () {
    expect(
      txtFiles.length,
      greaterThanOrEqualTo(10),
      reason: 'Sprint 2.2 needs ≥10 synthetic fixtures.',
    );
  });

  for (final File txt in txtFiles) {
    final String slug = txt.uri.pathSegments.last.replaceAll('.txt', '');
    final File jsonFile = File(txt.path.replaceAll('.txt', '.json'));

    group('fixture: $slug', () {
      late ScannedReceipt parsed;
      late Map<String, Object?> expected;

      setUpAll(() {
        final String raw = txt.readAsStringSync();
        expected = jsonDecode(jsonFile.readAsStringSync())
            as Map<String, Object?>;
        final OCRResult fake = OCRResult(
          rawText: raw,
          blocks: const <OCRTextBlock>[],
          confidence: 0.95,
          engine: OCREngine.mlKit,
        );
        parsed = parser.parse(fake, imagePath: '/tmp/$slug.jpg');
      });

      test('should detect the store name', () {
        final String? want = expected['storeName'] as String?;
        if (want == null) {
          expect(parsed.storeName, isNull);
        } else {
          expect(parsed.storeName, want);
        }
      });

      test('should detect the date', () {
        final String? want = expected['date'] as String?;
        if (want == null) {
          expect(parsed.date, isNull);
        } else {
          expect(parsed.date, isNotNull);
          final DateTime? parsedDate = parsed.date;
          expect(parsedDate, isNotNull);
          expect(parsedDate!.toIso8601String().substring(0, 10), want);
        }
      });

      test('should detect the currency', () {
        expect(parsed.currency, expected['currency']);
      });

      test('should detect the total amount', () {
        expect(parsed.total, expected['total']);
      });

      test('should extract at least the expected number of items', () {
        final int min = (expected['minItems']! as num).toInt();
        expect(
          parsed.items.length,
          greaterThanOrEqualTo(min),
          reason: 'Parsed ${parsed.items.length} items '
              '(${parsed.items.map((ScannedItem i) => i.name).join(", ")}) '
              'but expected ≥$min.',
        );
      });
    });
  }
}
