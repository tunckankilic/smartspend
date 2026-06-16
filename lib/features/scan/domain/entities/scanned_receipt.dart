import 'package:equatable/equatable.dart';

import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';

/// The structured output of the scan pipeline.
///
/// Sprint 2.1 only fills [imagePath] — the rest of the fields are populated
/// in Sprint 2.2 once the OCR engine is wired. [total] is in cents.
class ScannedReceipt extends Equatable {
  const ScannedReceipt({
    required this.imagePath,
    required this.items,
    required this.total,
    required this.currency,
    required this.rawText,
    required this.confidenceScore,
    this.storeName,
    this.date,
  });

  /// Construct an empty receipt anchored to a captured image. Used by the
  /// pre-OCR Sprint 2.1 flow so the bloc can move through the state machine
  /// without an engine plugged in.
  factory ScannedReceipt.pending(String imagePath) => ScannedReceipt(
    imagePath: imagePath,
    items: const <ScannedItem>[],
    total: 0,
    currency: '',
    rawText: '',
    confidenceScore: 0,
  );

  /// Absolute path to the captured / picked image on disk.
  final String imagePath;
  final String? storeName;
  final DateTime? date;
  final List<ScannedItem> items;

  /// Total in the smallest currency unit (kuruş / cent).
  final int total;
  final String currency;
  final String rawText;

  /// `0.0`–`1.0`. Below `0.70` the engine should hand off to the Gemini
  /// Edge Function fallback (wired in Sprint 2.2).
  final double confidenceScore;

  ScannedReceipt copyWith({
    String? imagePath,
    String? storeName,
    DateTime? date,
    List<ScannedItem>? items,
    int? total,
    String? currency,
    String? rawText,
    double? confidenceScore,
  }) {
    return ScannedReceipt(
      imagePath: imagePath ?? this.imagePath,
      storeName: storeName ?? this.storeName,
      date: date ?? this.date,
      items: items ?? this.items,
      total: total ?? this.total,
      currency: currency ?? this.currency,
      rawText: rawText ?? this.rawText,
      confidenceScore: confidenceScore ?? this.confidenceScore,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    imagePath,
    storeName,
    date,
    items,
    total,
    currency,
    rawText,
    confidenceScore,
  ];
}
