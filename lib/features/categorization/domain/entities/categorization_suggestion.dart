import 'package:equatable/equatable.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';

/// Where the suggestion came from. The UI uses this to label why a
/// category was preselected ("Mağazadan tahmin edildi", "Geçmişten
/// öğrenildi", ...) and the hybrid engine uses it to decide which
/// branch wins.
enum CategorizationSource {
  /// Pattern match on the store-name database
  /// (`assets/ml/store_categories.json`).
  keywordStore,

  /// Pattern match on item-name keywords (fallback when the store
  /// name yields nothing).
  keywordItem,

  /// On-device TF Lite model — currently a Sprint 4 stub that always
  /// returns 0 confidence. Sprint 9 will replace this with the trained
  /// model.
  tflite,

  /// User has corrected this store before; reused via
  /// `user_corrections` (Sprint 4 stub — table arrives in Sprint 6).
  userCorrection,

  /// No engine produced a usable confidence — caller should fall back
  /// to the default category.
  none,
}

/// Single result emitted by a [CategorizationEngine].
///
/// Confidence is in `[0.0, 1.0]`. The hybrid engine routes based on
/// thresholds documented on `HybridCategorizationEngine`.
class CategorizationSuggestion extends Equatable {
  const CategorizationSuggestion({
    required this.category,
    required this.confidence,
    required this.source,
    this.matchedPattern,
  });

  /// Empty suggestion — no engine matched. Callers should treat this
  /// as "use the user's default category instead".
  const CategorizationSuggestion.none()
      : category = null,
        confidence = 0.0,
        source = CategorizationSource.none,
        matchedPattern = null;

  final Category? category;
  final double confidence;
  final CategorizationSource source;

  /// The literal pattern that triggered the match (for telemetry +
  /// "we matched X" hints in the UI). Null for non-keyword sources.
  final String? matchedPattern;

  bool get hasMatch => category != null && confidence > 0;

  @override
  List<Object?> get props =>
      <Object?>[category, confidence, source, matchedPattern];
}
