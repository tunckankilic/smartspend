import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/data/engines/keyword_categorization_engine.dart';
import 'package:smartspend/features/categorization/data/store_database.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';

const String _kFixtureJson = '''
{
  "version": 1,
  "entries": [
    { "patterns": ["bim", "bim a.s"], "categoryIcon": "shopping_cart", "confidence": 0.95 },
    { "patterns": ["migros"], "categoryIcon": "shopping_cart", "confidence": 0.95 },
    { "patterns": ["shell"], "categoryIcon": "local_gas_station", "confidence": 0.9 },
    { "patterns": ["starbucks"], "categoryIcon": "coffee", "confidence": 0.97 },
    { "patterns": ["aldi"], "categoryIcon": "shopping_cart", "confidence": 0.95 }
  ],
  "itemKeywords": [
    { "patterns": ["benzin", "diesel"], "categoryIcon": "local_gas_station", "confidence": 0.85 },
    { "patterns": ["kahve", "espresso"], "categoryIcon": "coffee", "confidence": 0.75 }
  ]
}
''';

class _FixtureBundle extends CachingAssetBundle {
  _FixtureBundle();

  @override
  Future<ByteData> load(String key) async {
    throw UnimplementedError();
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      _kFixtureJson;
}

void main() {
  const Category market = Category(
    id: 1,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    isCustom: false,
  );
  const Category fuel = Category(
    id: 2,
    name: 'Yakıt',
    icon: 'local_gas_station',
    color: 0xFF607D8B,
    isCustom: false,
  );
  const Category coffee = Category(
    id: 3,
    name: 'Kahve',
    icon: 'coffee',
    color: 0xFF795548,
    isCustom: false,
  );
  const List<Category> cats = <Category>[market, fuel, coffee];

  late KeywordCategorizationEngine engine;

  setUp(() async {
    engine = KeywordCategorizationEngine(
      database: StoreDatabase(bundle: _FixtureBundle()),
    );
    await engine.warmUp();
  });

  group('store-name match', () {
    test('exact lowercase match should return full confidence', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'BIM',
        itemNames: const <String>[],
        availableCategories: cats,
      );

      expect(s.category, market);
      expect(s.confidence, closeTo(0.95, 1e-9));
      expect(s.source, CategorizationSource.keywordStore);
      expect(s.matchedPattern, 'bim');
    });

    test('case-insensitive match should still hit', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'Migros',
        itemNames: const <String>[],
        availableCategories: cats,
      );

      expect(s.category, market);
      expect(s.confidence, closeTo(0.95, 1e-9));
    });

    test('substring match should drop confidence by 20%', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'BIM A101 EKSPRES',
        itemNames: const <String>[],
        availableCategories: cats,
      );

      expect(s.category, market);
      expect(s.confidence, closeTo(0.95 * 0.8, 1e-9));
    });

    test('whitespace and casing should be normalized', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: '  STARBUCKS    COFFEE  ',
        itemNames: const <String>[],
        availableCategories: cats,
      );

      expect(s.category, coffee);
    });

    test('unknown store + no items returns no-match', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'Bilinmeyen Yer',
        itemNames: const <String>[],
        availableCategories: cats,
      );

      expect(s.hasMatch, isFalse);
      expect(s.source, CategorizationSource.none);
    });

    test('empty store name with items falls back to item keywords',
        () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: null,
        itemNames: const <String>['Benzin 95 oktan'],
        availableCategories: cats,
      );

      expect(s.category, fuel);
      expect(s.source, CategorizationSource.keywordItem);
      expect(s.confidence, closeTo(0.85 * 0.85, 1e-9));
    });
  });

  group('item-name fallback', () {
    test('item keyword should match when store is unknown', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'Random Cafe',
        itemNames: const <String>['Espresso Doppio'],
        availableCategories: cats,
      );

      expect(s.category, coffee);
      expect(s.source, CategorizationSource.keywordItem);
    });

    test('store match wins over item keyword', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'Shell',
        itemNames: const <String>['Kahve', 'Çikolata'],
        availableCategories: cats,
      );

      expect(s.category, fuel);
      expect(s.source, CategorizationSource.keywordStore);
    });
  });

  group('edge cases', () {
    test('empty availableCategories returns no-match', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'BIM',
        itemNames: const <String>[],
        availableCategories: const <Category>[],
      );

      expect(s.hasMatch, isFalse);
    });

    test('missing matching icon in cats list yields no-match', () async {
      const Category onlyOther = Category(
        id: 99,
        name: 'Diğer',
        icon: 'more_horiz',
        color: 0,
        isCustom: false,
      );
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'BIM',
        itemNames: const <String>[],
        availableCategories: const <Category>[onlyOther],
      );

      expect(s.hasMatch, isFalse);
    });

    test('blank store name and empty items returns no-match', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: '   ',
        itemNames: const <String>[],
        availableCategories: cats,
      );

      expect(s.hasMatch, isFalse);
    });

    test('blank item names are skipped', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: null,
        itemNames: const <String>['', '   ', 'kahve seçkisi'],
        availableCategories: cats,
      );

      expect(s.category, coffee);
    });

    test('confidence is clamped to [0, 1]', () async {
      final CategorizationSuggestion s = await engine.suggest(
        storeName: 'BIM',
        itemNames: const <String>[],
        availableCategories: cats,
      );

      expect(s.confidence, lessThanOrEqualTo(1.0));
      expect(s.confidence, greaterThanOrEqualTo(0.0));
    });
  });
}
