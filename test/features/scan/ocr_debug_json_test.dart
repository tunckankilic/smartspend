import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/services/ocr_debug_recorder.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';

/// The debug-JSON round-trip itself is covered in the `receipt_ocr` package;
/// this file pins the app-side guarantee: the recorder is compiled inert in
/// store builds.
void main() {
  const OCRResult mlKitResult = OCRResult(
    rawText: 'BİM A.Ş.\nTAM YAGLI SUT 1L *37,50\nTOPLAM *37,50',
    confidence: 0.87,
    engine: OCREngine.mlKit,
    blocks: <OCRTextBlock>[
      OCRTextBlock(
        text: 'BİM A.Ş.',
        confidence: 0.95,
        boundingBox: OCRBoundingBox(
          left: 12.5,
          top: 8,
          right: 220.25,
          bottom: 42,
        ),
      ),
    ],
  );

  group('OcrDebugRecorder', () {
    test('should stay inert when OCR_DEBUG is not defined', () {
      // Tests run without --dart-define=OCR_DEBUG=true, which is exactly
      // the store-build configuration: recording must be a no-op.
      final OcrDebugRecorder recorder = OcrDebugRecorder()..record(mlKitResult);

      expect(recorder.lastJson, isNull);
    });
  });
}
