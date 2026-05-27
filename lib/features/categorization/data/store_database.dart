import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart' show AssetBundle;

/// Parsed representation of one entry in `assets/ml/store_categories.json`.
class StorePattern extends Equatable {
  const StorePattern({
    required this.patterns,
    required this.categoryIcon,
    required this.confidence,
  });

  /// Lower-cased haystacks to match against the normalized store name.
  final List<String> patterns;

  /// Icon name — looked up in [CategoryRepository] to resolve a [Category].
  final String categoryIcon;

  /// Engine-supplied confidence; the keyword engine multiplies by a
  /// per-match factor (exact = 1.0, contains = 0.8).
  final double confidence;

  @override
  List<Object?> get props => <Object?>[patterns, categoryIcon, confidence];
}

/// Loader for `assets/ml/store_categories.json`.
///
/// Cached after the first load so the second scan in a session doesn't
/// re-parse 260+ entries. Tests can construct an instance with a custom
/// [AssetBundle] (or call [parseJson] directly) to avoid IO.
class StoreDatabase {
  StoreDatabase({required AssetBundle bundle, String? assetPath})
      : this._(bundle, assetPath ?? _kDefaultAssetPath);

  StoreDatabase._(this._bundle, this._assetPath);

  static const String _kDefaultAssetPath = 'assets/ml/store_categories.json';

  final AssetBundle _bundle;
  final String _assetPath;

  List<StorePattern>? _storeEntries;
  List<StorePattern>? _itemEntries;

  /// Reload from disk; subsequent calls return the cached copy.
  Future<void> load() async {
    if (_storeEntries != null) return;
    final String raw = await _bundle.loadString(_assetPath);
    final (List<StorePattern> store, List<StorePattern> items) = parseJson(raw);
    _storeEntries = store;
    _itemEntries = items;
  }

  /// All store-name patterns; empty until [load] completes.
  List<StorePattern> get storeEntries =>
      _storeEntries ?? const <StorePattern>[];

  /// Item-name keyword fallback patterns.
  List<StorePattern> get itemEntries =>
      _itemEntries ?? const <StorePattern>[];

  /// Pure parser; surfaced for tests so they can build a database
  /// without an [AssetBundle].
  static (List<StorePattern>, List<StorePattern>) parseJson(String raw) {
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    final List<StorePattern> store = _decodeList(json['entries']);
    final List<StorePattern> items = _decodeList(json['itemKeywords']);
    return (store, items);
  }

  static List<StorePattern> _decodeList(Object? source) {
    if (source is! List<dynamic>) return const <StorePattern>[];
    final List<StorePattern> out = <StorePattern>[];
    for (final dynamic entry in source) {
      if (entry is! Map<String, dynamic>) continue;
      final List<dynamic>? rawPatterns =
          entry['patterns'] as List<dynamic>?;
      if (rawPatterns == null) continue;
      final List<String> patterns = rawPatterns
          .whereType<String>()
          .map((String s) => s.toLowerCase())
          .toList(growable: false);
      final String? icon = entry['categoryIcon'] as String?;
      final num? confidence = entry['confidence'] as num?;
      if (icon == null || confidence == null) continue;
      out.add(
        StorePattern(
          patterns: patterns,
          categoryIcon: icon,
          confidence: confidence.toDouble(),
        ),
      );
    }
    return out;
  }
}
