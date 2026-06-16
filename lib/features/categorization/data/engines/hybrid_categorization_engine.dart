// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/engines/categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';

/// Routes between [keyword] and [tflite] engines.
///
/// Decision matrix:
///
/// | keyword confidence | TF Lite confidence | winner |
/// |--------------------|--------------------|--------|
/// | `≥ 0.85`           | any                | keyword (high-trust pattern)  |
/// | `< 0.85`           | `> keyword conf`   | tflite                        |
/// | both `< 0.30`      |                    | none                          |
/// | otherwise          |                    | keyword (with whatever it has) |
///
/// The keyword threshold (`0.85`) matches the confidence at which the
/// store JSON considers a brand-name an unambiguous hit (e.g. "BİM",
/// "Aldi"). TF Lite currently always returns no-match (Sprint 4 stub),
/// so the practical behaviour today is "keyword or none".
class HybridCategorizationEngine implements CategorizationEngine {
  const HybridCategorizationEngine({
    required CategorizationEngine keyword,
    required CategorizationEngine tflite,
    double highTrustThreshold = 0.85,
    double minimumThreshold = 0.30,
  })  : _keyword = keyword,
        _tflite = tflite,
        _highTrust = highTrustThreshold,
        _minimum = minimumThreshold;

  final CategorizationEngine _keyword;
  final CategorizationEngine _tflite;
  final double _highTrust;
  final double _minimum;

  @override
  Future<void> warmUp() async {
    await Future.wait<void>(<Future<void>>[
      _keyword.warmUp(),
      _tflite.warmUp(),
    ]);
  }

  @override
  Future<CategorizationSuggestion> suggest({
    required String? storeName,
    required List<String> itemNames,
    required List<Category> availableCategories,
  }) async {
    final CategorizationSuggestion kw = await _keyword.suggest(
      storeName: storeName,
      itemNames: itemNames,
      availableCategories: availableCategories,
    );

    if (kw.hasMatch && kw.confidence >= _highTrust) return kw;

    final CategorizationSuggestion ml = await _tflite.suggest(
      storeName: storeName,
      itemNames: itemNames,
      availableCategories: availableCategories,
    );

    if (ml.hasMatch && ml.confidence > kw.confidence) return ml;
    if (kw.hasMatch && kw.confidence >= _minimum) return kw;

    return const CategorizationSuggestion.none();
  }
}
