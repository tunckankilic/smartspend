import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/receipts/presentation/bloc/receipt_archive_bloc.dart';

/// Equality contracts for [ReceiptArchiveEvent] subtypes.
void main() {
  group('ReceiptArchiveEvent equality', () {
    test('should treat value-less events as equal', () {
      expect(
        const ReceiptArchiveSubscribed(),
        const ReceiptArchiveSubscribed(),
      );
      expect(
        const ReceiptArchiveViewToggled(),
        const ReceiptArchiveViewToggled(),
      );
    });

    test('should compare SearchChanged by query', () {
      expect(
        const ReceiptArchiveSearchChanged(query: 'bim'),
        const ReceiptArchiveSearchChanged(query: 'bim'),
      );
      expect(
        const ReceiptArchiveSearchChanged(query: 'bim'),
        isNot(const ReceiptArchiveSearchChanged(query: 'a101')),
      );
    });

    test('should compare DateRangeChanged by both bounds', () {
      final DateTime from = DateTime.utc(2026, 1, 1);
      final DateTime to = DateTime.utc(2026, 1, 31);
      expect(
        ReceiptArchiveDateRangeChanged(from: from, to: to),
        ReceiptArchiveDateRangeChanged(from: from, to: to),
      );
      expect(
        ReceiptArchiveDateRangeChanged(from: from),
        isNot(ReceiptArchiveDateRangeChanged(to: to)),
      );
    });
  });
}
