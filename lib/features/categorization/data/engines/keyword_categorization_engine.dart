import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/data/store_database.dart';
import 'package:smartspend/features/categorization/domain/engines/categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';

/// Rule-based categorizer.
///
/// Matching order:
/// 1. **Exact store-name match** (case-insensitive, post-normalize) →
///    full confidence as declared in the JSON.
/// 2. **Substring store-name match** → confidence × 0.8.
/// 3. **Item-name keyword match** → confidence × 0.85 (slightly lower
///    than store match because item text is noisier).
///
/// Whichever branch fires first, the engine returns one
/// [CategorizationSuggestion]; downstream Hybrid logic decides whether
/// it's strong enough to act on.
class KeywordCategorizationEngine implements CategorizationEngine {
  KeywordCategorizationEngine({required StoreDatabase database})
      : _db = database;

  final StoreDatabase _db;

  @override
  Future<void> warmUp() => _db.load();

  @override
  Future<CategorizationSuggestion> suggest({
    required String? storeName,
    required List<String> itemNames,
    required List<Category> availableCategories,
  }) async {
    await _db.load();

    if (availableCategories.isEmpty) {
      return const CategorizationSuggestion.none();
    }

    final String? haystack = _normalize(storeName);

    if (haystack != null && haystack.isNotEmpty) {
      final CategorizationSuggestion? storeMatch = _matchStore(
        haystack: haystack,
        availableCategories: availableCategories,
      );
      if (storeMatch != null) return storeMatch;
    }

    // Fallback: scan item names for grocery / fuel / etc keywords.
    if (itemNames.isNotEmpty) {
      final CategorizationSuggestion? itemMatch = _matchItems(
        items: itemNames,
        availableCategories: availableCategories,
      );
      if (itemMatch != null) return itemMatch;
    }

    return const CategorizationSuggestion.none();
  }

  CategorizationSuggestion? _matchStore({
    required String haystack,
    required List<Category> availableCategories,
  }) {
    for (final StorePattern entry in _db.storeEntries) {
      for (final String pattern in entry.patterns) {
        if (pattern.isEmpty) continue;
        final bool exact = haystack == pattern;
        final bool contains = !exact && haystack.contains(pattern);
        if (!exact && !contains) continue;

        final Category? cat = _resolveCategory(
          icon: entry.categoryIcon,
          availableCategories: availableCategories,
        );
        if (cat == null) continue;

        final double conf = (exact ? entry.confidence : entry.confidence * 0.8)
            .clamp(0.0, 1.0);
        return CategorizationSuggestion(
          category: cat,
          confidence: conf,
          source: CategorizationSource.keywordStore,
          matchedPattern: pattern,
        );
      }
    }
    return null;
  }

  CategorizationSuggestion? _matchItems({
    required List<String> items,
    required List<Category> availableCategories,
  }) {
    for (final String rawItem in items) {
      final String item = rawItem.toLowerCase().trim();
      if (item.isEmpty) continue;
      for (final StorePattern entry in _db.itemEntries) {
        for (final String pattern in entry.patterns) {
          if (pattern.isEmpty) continue;
          if (!item.contains(pattern)) continue;
          final Category? cat = _resolveCategory(
            icon: entry.categoryIcon,
            availableCategories: availableCategories,
          );
          if (cat == null) continue;
          final double conf =
              (entry.confidence * 0.85).clamp(0.0, 1.0);
          return CategorizationSuggestion(
            category: cat,
            confidence: conf,
            source: CategorizationSource.keywordItem,
            matchedPattern: pattern,
          );
        }
      }
    }
    return null;
  }

  /// Normalize for matching: lowercase, trim, collapse whitespace.
  /// Anything else (accent folding, currency-suffix stripping) belongs
  /// in the ReceiptParser before we ever get the string.
  String? _normalize(String? input) {
    if (input == null) return null;
    final String collapsed =
        input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.isEmpty ? null : collapsed;
  }

  Category? _resolveCategory({
    required String icon,
    required List<Category> availableCategories,
  }) {
    for (final Category c in availableCategories) {
      if (c.icon == icon) return c;
    }
    return null;
  }
}
