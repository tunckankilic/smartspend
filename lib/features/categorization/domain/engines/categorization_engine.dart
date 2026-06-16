import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';

/// Abstract surface for any "guess the category" strategy.
///
/// Implementations:
/// * `KeywordCategorizationEngine` — store-name + item-name pattern match.
/// * `TFLiteCategorizationEngine` — on-device ML (Sprint 9 will ship the
///   trained model; the Sprint 4 stub returns no-match).
/// * `HybridCategorizationEngine` — routes between the two with a
///   confidence threshold; this is the engine the rest of the app uses.
///
/// Sprint 6 will add a `UserCorrectionEngine` that mines past overrides
/// for per-user store mappings.
abstract class CategorizationEngine {
  /// Called once at app startup. Lets engines load JSON / TF Lite
  /// interpreters before the first scan arrives so the user never waits.
  Future<void> warmUp();

  /// Returns the engine's best guess for `storeName` + the receipt's
  /// item names. Either input can be empty; the engine should still
  /// return [CategorizationSuggestion.none] rather than throwing.
  ///
  /// `availableCategories` is the user's current category list (defaults
  /// + custom). The engine MUST only return a category that appears in
  /// this list — never a synthetic one.
  Future<CategorizationSuggestion> suggest({
    required String? storeName,
    required List<String> itemNames,
    required List<Category> availableCategories,
  });
}
