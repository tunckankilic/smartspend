import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/engines/categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';

/// Sprint 4 stub for the on-device TF Lite categorizer.
///
/// The real implementation will:
///   1. Load `assets/ml/store_categorizer.tflite` via `tflite_flutter`
///      (added in Sprint 9 when the training notebook produces a model).
///   2. Tokenize `storeName + ' ' + itemNames.join(' ')` with a vocab
///      shipped alongside the model.
///   3. Run inference → softmax probabilities → top-1 with the matching
///      icon mapped to a [Category] from `availableCategories`.
///
/// Until then [suggest] always returns no-match so the hybrid engine
/// falls back to keyword. This keeps the interface stable for the rest
/// of the app and avoids pulling in a native plugin we don't yet use.
class TFLiteCategorizationEngine implements CategorizationEngine {
  const TFLiteCategorizationEngine();

  @override
  Future<void> warmUp() async {
    // No-op until Sprint 9 wires the interpreter.
  }

  @override
  Future<CategorizationSuggestion> suggest({
    required String? storeName,
    required List<String> itemNames,
    required List<Category> availableCategories,
  }) async {
    return const CategorizationSuggestion.none();
  }
}
