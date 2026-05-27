import 'dart:io';

import 'package:equatable/equatable.dart';

/// Raw output of an OCR engine.
///
/// Stays free of `google_mlkit_*` types so the parser layer can work with
/// either ML Kit (on-device) or the Gemini Edge Function fallback without
/// caring which engine produced it.
class OCRResult extends Equatable {
  const OCRResult({
    required this.rawText,
    required this.blocks,
    required this.confidence,
    required this.engine,
  });

  /// The full recognized text, newline-joined in reading order.
  final String rawText;

  /// Per-block breakdown — useful for position-aware parsing in later
  /// sprints (e.g. amount alignment on the right edge of the receipt).
  final List<OCRTextBlock> blocks;

  /// `0.0`–`1.0`. Average across [blocks] for ML Kit; Gemini returns a
  /// self-reported score (capped at `1.0`).
  final double confidence;

  /// Which engine produced this result. Drives the hybrid datasource's
  /// fallback decision and shows up in Sentry breadcrumbs.
  final OCREngine engine;

  @override
  List<Object?> get props => <Object?>[rawText, blocks, confidence, engine];
}

class OCRTextBlock extends Equatable {
  const OCRTextBlock({
    required this.text,
    required this.confidence,
    this.boundingBox,
  });

  final String text;
  final double confidence;

  /// Optional — Gemini doesn't expose bounding boxes; ML Kit does.
  final OCRBoundingBox? boundingBox;

  @override
  List<Object?> get props => <Object?>[text, confidence, boundingBox];
}

/// Decoupled rectangle so we don't leak `dart:ui` into the data layer.
class OCRBoundingBox extends Equatable {
  const OCRBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  List<Object?> get props => <Object?>[left, top, right, bottom];
}

enum OCREngine { mlKit, gemini }

/// Contract every OCR engine implements.
abstract class OCRDataSource {
  Future<OCRResult> recognizeText(File image);
}
