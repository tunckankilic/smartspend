import 'package:receipt_ocr/receipt_ocr.dart';

import 'package:smartspend/core/constants/app_constants.dart';

/// Holds the most recent **on-device** OCR engine output so the hidden
/// export trigger on the scan result screen can share it as JSON — the raw
/// material of the OCR eval corpus (`tools/ocr_corpus/device_json/`).
///
/// Inert by design unless the build was compiled with
/// `--dart-define=OCR_DEBUG=true` (see [AppConstants.ocrDebugEnabled]):
/// [record] becomes a no-op, [lastJson] stays `null`, and nothing is ever
/// retained. The captured JSON contains the full receipt text, so it must
/// never be logged or sent to Sentry — it leaves the device only via the
/// user-initiated share sheet.
class OcrDebugRecorder {
  String? _lastJson;

  /// Pretty-printed [OCRResult.toDebugJson] of the last recorded scan, or
  /// `null` when nothing was recorded (or the flag is off).
  String? get lastJson => _lastJson;

  /// Captures [result] for a later export. No-op in non-debug builds.
  void record(OCRResult result) {
    if (!AppConstants.ocrDebugEnabled) return;
    _lastJson = result.toDebugJsonString();
  }
}
