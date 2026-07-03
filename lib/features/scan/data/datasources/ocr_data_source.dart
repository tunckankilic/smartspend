import 'dart:io';

import 'package:receipt_ocr/receipt_ocr.dart';

/// The OCR intelligence layer — result models (`OCRResult`, blocks,
/// bounding boxes), `ReceiptParser`/`ParsedReceipt` and the debug-JSON
/// round-trip — lives in the **private** pure-Dart `receipt_ocr` package
/// (this repo is public; that one is the app's core IP). Re-exported here
/// so existing imports keep working unchanged.
export 'package:receipt_ocr/receipt_ocr.dart';

/// Contract every OCR engine implements.
///
/// Stays in the app (not the package): it deals in `dart:io` [File]s coming
/// from the camera/gallery pipeline, and its implementations bind to
/// platform plugins (ML Kit) or the Supabase Edge Function (Gemini).
abstract class OCRDataSource {
  Future<OCRResult> recognizeText(File image);
}
