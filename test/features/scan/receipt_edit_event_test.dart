import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/presentation/bloc/receipt_edit_bloc.dart';

/// Equality contracts for [ReceiptEditEvent] subtypes.
void main() {
  const ScannedItem item = ScannedItem(
    name: 'EKMEK',
    quantity: 1,
    unitPrice: 450,
    totalPrice: 450,
  );

  const ScannedReceipt receipt = ScannedReceipt(
    imagePath: '/tmp/receipt.jpg',
    items: <ScannedItem>[item],
    total: 450,
    currency: 'TRY',
    rawText: 'EKMEK 4,50\nTOPLAM 4,50',
    confidenceScore: 0.9,
  );

  group('ReceiptEditEvent equality', () {
    test('should treat value-less events as equal', () {
      expect(const ReceiptItemAdded(), const ReceiptItemAdded());
      expect(const ReceiptEditSubmitted(), const ReceiptEditSubmitted());
    });

    test('should compare EditStarted by scanned receipt', () {
      expect(
        const ReceiptEditStarted(receipt: receipt),
        const ReceiptEditStarted(receipt: receipt),
      );
    });

    test('should compare field edits by value', () {
      expect(
        const ReceiptStoreNameChanged(storeName: 'BİM'),
        const ReceiptStoreNameChanged(storeName: 'BİM'),
      );
      expect(
        const ReceiptStoreNameChanged(storeName: 'BİM'),
        isNot(const ReceiptStoreNameChanged(storeName: 'A101')),
      );
      final DateTime date = DateTime.utc(2026, 7, 7);
      expect(ReceiptDateChanged(date: date), ReceiptDateChanged(date: date));
      expect(
        const ReceiptCurrencyChanged(currency: 'TRY'),
        isNot(const ReceiptCurrencyChanged(currency: 'EUR')),
      );
      expect(
        const ReceiptDefaultCategoryChanged(categoryId: 2),
        const ReceiptDefaultCategoryChanged(categoryId: 2),
      );
    });

    test('should compare item edits by index and payload', () {
      expect(
        const ReceiptItemRemoved(index: 0),
        const ReceiptItemRemoved(index: 0),
      );
      expect(
        const ReceiptItemRemoved(index: 0),
        isNot(const ReceiptItemRemoved(index: 1)),
      );
      expect(
        const ReceiptItemUpdated(index: 0, item: item),
        const ReceiptItemUpdated(index: 0, item: item),
      );
      expect(
        const ReceiptItemCategoryChanged(index: 0, categoryId: 3),
        const ReceiptItemCategoryChanged(index: 0, categoryId: 3),
      );
      expect(
        const ReceiptItemCategoryChanged(index: 0, categoryId: 3),
        isNot(const ReceiptItemCategoryChanged(index: 0, categoryId: null)),
      );
    });

    test('should compare CategoryCreated by name, icon and color', () {
      expect(
        const ReceiptCategoryCreated(
          name: 'Kitap',
          icon: 'book',
          color: 0xFF2196F3,
        ),
        const ReceiptCategoryCreated(
          name: 'Kitap',
          icon: 'book',
          color: 0xFF2196F3,
        ),
      );
    });
  });
}
