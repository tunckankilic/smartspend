import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';

/// On-device OCR via Google ML Kit Text Recognition. 100% offline, zero
/// per-request cost — this is always the primary engine.
class MLKitOCRDataSource implements OCRDataSource {
  MLKitOCRDataSource({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  /// ML Kit doesn't expose a confidence score per block, so we synthesize
  /// one from text density: longer blocks with valid characters score
  /// higher. This is good enough to gate the Gemini fallback (we just need
  /// a "should I escalate?" signal, not calibrated probability).
  static const double _minBlockChars = 4;

  @override
  Future<OCRResult> recognizeText(File image) async {
    try {
      final InputImage input = InputImage.fromFile(image);
      final RecognizedText recognized = await _recognizer.processImage(input);

      final List<OCRTextBlock> blocks = recognized.blocks
          .map(_mapBlock)
          .toList(growable: false);

      final double confidence = _scoreConfidence(blocks);

      return OCRResult(
        rawText: recognized.text,
        blocks: blocks,
        confidence: confidence,
        engine: OCREngine.mlKit,
      );
    } on Exception catch (e) {
      throw OCRException(message: 'ML Kit text recognition failed: $e');
    }
  }

  OCRTextBlock _mapBlock(TextBlock block) {
    return OCRTextBlock(
      text: block.text,
      confidence: _blockConfidence(block.text),
      boundingBox: OCRBoundingBox(
        left: block.boundingBox.left,
        top: block.boundingBox.top,
        right: block.boundingBox.right,
        bottom: block.boundingBox.bottom,
      ),
    );
  }

  /// Cheap heuristic: short blocks (< 4 chars) and pure-symbol blocks
  /// drag confidence down, which is exactly what we want to detect
  /// blurry / glare-damaged receipts that need the Gemini fallback.
  double _blockConfidence(String text) {
    final String trimmed = text.trim();
    if (trimmed.length < _minBlockChars) return 0.4;
    final int alpha = trimmed.runes.where(_isAlphaNum).length;
    final double ratio = alpha / trimmed.length;
    return ratio.clamp(0.4, 0.98);
  }

  bool _isAlphaNum(int rune) {
    return (rune >= 0x30 && rune <= 0x39) || // 0-9
        (rune >= 0x41 && rune <= 0x5A) || // A-Z
        (rune >= 0x61 && rune <= 0x7A) || // a-z
        rune == 0xC7 ||
        rune == 0xE7 || // Ç ç
        rune == 0xD6 ||
        rune == 0xF6 || // Ö ö
        rune == 0xDC ||
        rune == 0xFC || // Ü ü
        rune == 0x11E ||
        rune == 0x11F || // Ğ ğ
        rune == 0x130 ||
        rune == 0x131 || // İ ı
        rune == 0x15E ||
        rune == 0x15F || // Ş ş
        rune == 0xDF; // ß
  }

  double _scoreConfidence(List<OCRTextBlock> blocks) {
    if (blocks.isEmpty) return 0;
    final double avg =
        blocks.map((OCRTextBlock b) => b.confidence).reduce(_sum) /
        blocks.length;
    return double.parse(avg.toStringAsFixed(3));
  }

  double _sum(double a, double b) => a + b;

  /// Release native resources. Call from the DI shutdown hook.
  Future<void> close() => _recognizer.close();
}
