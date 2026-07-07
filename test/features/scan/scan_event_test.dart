import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/usecases/scan_receipt.dart';
import 'package:smartspend/features/scan/domain/usecases/usecase.dart';
import 'package:smartspend/features/scan/presentation/bloc/scan_bloc.dart';

/// Equality contracts for [ScanEvent] subtypes.
void main() {
  const ScannedReceipt receipt = ScannedReceipt(
    imagePath: '/tmp/receipt.jpg',
    items: <ScannedItem>[],
    total: 450,
    currency: 'TRY',
    rawText: 'EKMEK 4,50\nTOPLAM 4,50',
    confidenceScore: 0.9,
  );

  group('ScanEvent equality', () {
    test('should treat value-less events as equal', () {
      expect(const CameraOpened(), const CameraOpened());
      expect(const GalleryOpened(), const GalleryOpened());
      expect(const ScanStarted(), const ScanStarted());
      expect(const ScanReset(), const ScanReset());
    });

    test('should compare ImageCaptured by file path', () {
      expect(
        ImageCaptured(image: File('/tmp/a.jpg')),
        ImageCaptured(image: File('/tmp/a.jpg')),
      );
      expect(
        ImageCaptured(image: File('/tmp/a.jpg')),
        isNot(ImageCaptured(image: File('/tmp/b.jpg'))),
      );
    });

    test('should compare review events by receipt payload', () {
      expect(
        const ResultEdited(receipt: receipt),
        const ResultEdited(receipt: receipt),
      );
      expect(
        const ReceiptConfirmed(receipt: receipt),
        const ReceiptConfirmed(receipt: receipt),
      );
    });

    test('should compare ScanReceiptParams by image path', () {
      expect(
        ScanReceiptParams(image: File('/tmp/a.jpg')),
        ScanReceiptParams(image: File('/tmp/a.jpg')),
      );
      expect(
        ScanReceiptParams(image: File('/tmp/a.jpg')),
        isNot(ScanReceiptParams(image: File('/tmp/b.jpg'))),
      );
      expect(const NoParams(), const NoParams());
    });
  });
}
