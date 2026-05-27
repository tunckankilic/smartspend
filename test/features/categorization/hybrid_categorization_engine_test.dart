import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/data/engines/hybrid_categorization_engine.dart';
import 'package:smartspend/features/categorization/data/engines/tflite_categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/engines/categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';

class _StubEngine implements CategorizationEngine {
  _StubEngine(this._suggestion);

  final CategorizationSuggestion _suggestion;
  int warmUpCount = 0;
  int suggestCount = 0;

  @override
  Future<void> warmUp() async {
    warmUpCount++;
  }

  @override
  Future<CategorizationSuggestion> suggest({
    required String? storeName,
    required List<String> itemNames,
    required List<Category> availableCategories,
  }) async {
    suggestCount++;
    return _suggestion;
  }
}

void main() {
  const Category market = Category(
    id: 1,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0,
    isCustom: false,
  );
  const Category coffee = Category(
    id: 2,
    name: 'Kahve',
    icon: 'coffee',
    color: 0,
    isCustom: false,
  );

  group('routing matrix', () {
    test('keyword ≥ highTrust short-circuits TF Lite', () async {
      final _StubEngine kw = _StubEngine(
        const CategorizationSuggestion(
          category: market,
          confidence: 0.95,
          source: CategorizationSource.keywordStore,
        ),
      );
      final _StubEngine ml = _StubEngine(
        const CategorizationSuggestion.none(),
      );
      final HybridCategorizationEngine engine = HybridCategorizationEngine(
        keyword: kw,
        tflite: ml,
      );

      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'BIM',
        itemNames: const <String>[],
        availableCategories: const <Category>[market],
      );

      expect(s.category, market);
      expect(s.source, CategorizationSource.keywordStore);
      expect(ml.suggestCount, 0);
    });

    test('keyword < highTrust + TF Lite higher confidence wins', () async {
      final _StubEngine kw = _StubEngine(
        const CategorizationSuggestion(
          category: market,
          confidence: 0.4,
          source: CategorizationSource.keywordStore,
        ),
      );
      final _StubEngine ml = _StubEngine(
        const CategorizationSuggestion(
          category: coffee,
          confidence: 0.7,
          source: CategorizationSource.tflite,
        ),
      );
      final HybridCategorizationEngine engine = HybridCategorizationEngine(
        keyword: kw,
        tflite: ml,
      );

      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'whatever',
        itemNames: const <String>[],
        availableCategories: const <Category>[market, coffee],
      );

      expect(s.category, coffee);
      expect(s.source, CategorizationSource.tflite);
    });

    test('keyword < highTrust + TF Lite weaker keeps keyword', () async {
      final _StubEngine kw = _StubEngine(
        const CategorizationSuggestion(
          category: market,
          confidence: 0.6,
          source: CategorizationSource.keywordStore,
        ),
      );
      final _StubEngine ml = _StubEngine(
        const CategorizationSuggestion(
          category: coffee,
          confidence: 0.4,
          source: CategorizationSource.tflite,
        ),
      );
      final HybridCategorizationEngine engine = HybridCategorizationEngine(
        keyword: kw,
        tflite: ml,
      );

      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'whatever',
        itemNames: const <String>[],
        availableCategories: const <Category>[market, coffee],
      );

      expect(s.category, market);
    });

    test('both below minimum threshold returns none', () async {
      final _StubEngine kw = _StubEngine(
        const CategorizationSuggestion(
          category: market,
          confidence: 0.1,
          source: CategorizationSource.keywordStore,
        ),
      );
      final _StubEngine ml = _StubEngine(
        const CategorizationSuggestion(
          category: coffee,
          confidence: 0.05,
          source: CategorizationSource.tflite,
        ),
      );
      final HybridCategorizationEngine engine = HybridCategorizationEngine(
        keyword: kw,
        tflite: ml,
      );

      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'whatever',
        itemNames: const <String>[],
        availableCategories: const <Category>[market, coffee],
      );

      expect(s.hasMatch, isFalse);
      expect(s.source, CategorizationSource.none);
    });

    test('both engines return none-match → none', () async {
      final _StubEngine kw = _StubEngine(
        const CategorizationSuggestion.none(),
      );
      final _StubEngine ml = _StubEngine(
        const CategorizationSuggestion.none(),
      );
      final HybridCategorizationEngine engine = HybridCategorizationEngine(
        keyword: kw,
        tflite: ml,
      );

      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'whatever',
        itemNames: const <String>[],
        availableCategories: const <Category>[market],
      );

      expect(s.hasMatch, isFalse);
    });
  });

  group('warmUp', () {
    test('warms up both delegates in parallel', () async {
      final _StubEngine kw = _StubEngine(
        const CategorizationSuggestion.none(),
      );
      final _StubEngine ml = _StubEngine(
        const CategorizationSuggestion.none(),
      );
      final HybridCategorizationEngine engine = HybridCategorizationEngine(
        keyword: kw,
        tflite: ml,
      );

      await engine.warmUp();

      expect(kw.warmUpCount, 1);
      expect(ml.warmUpCount, 1);
    });
  });

  group('TFLite stub', () {
    test('always returns no-match (Sprint 4 stub)', () async {
      const TFLiteCategorizationEngine engine = TFLiteCategorizationEngine();
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'BIM',
        itemNames: const <String>['kahve'],
        availableCategories: const <Category>[market],
      );

      expect(s.hasMatch, isFalse);
      expect(s.source, CategorizationSource.none);
    });

    test('warmUp is a no-op and never throws', () async {
      const TFLiteCategorizationEngine engine = TFLiteCategorizationEngine();
      await engine.warmUp();
    });
  });
}
