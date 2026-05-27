import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';

/// Keyword → auto-tag dictionary. Lower-case, ASCII-folded where helpful.
///
/// Lookup is "phrase appears anywhere in the input text"; multiple
/// phrases can fire for the same input. The use case dedupes against
/// the caller-supplied `existingTags` list (case-insensitive).
const Map<String, String> _kKeywordToTag = <String, String>{
  'kahve': 'kahve',
  'coffee': 'kahve',
  'espresso': 'kahve',
  'latte': 'kahve',
  'cappuccino': 'kahve',
  'iş yemeği': 'iş',
  'is yemegi': 'iş',
  'business lunch': 'iş',
  'meeting': 'iş',
  'toplantı': 'iş',
  'toplanti': 'iş',
  'öğle yemeği': 'yemek',
  'ogle yemegi': 'yemek',
  'lunch': 'yemek',
  'dinner': 'yemek',
  'akşam yemeği': 'yemek',
  'aksam yemegi': 'yemek',
  'kira': 'kira',
  'rent': 'kira',
  'fatura': 'fatura',
  'invoice': 'fatura',
  'bill': 'fatura',
  'rechnung': 'fatura',
  'taksi': 'ulaşım',
  'uber': 'ulaşım',
  'bolt': 'ulaşım',
  'taxi': 'ulaşım',
  'benzin': 'yakıt',
  'diesel': 'yakıt',
  'dizel': 'yakıt',
  'fuel': 'yakıt',
  'market': 'market',
  'grocery': 'market',
  'eczane': 'sağlık',
  'apotheke': 'sağlık',
  'pharmacy': 'sağlık',
};

class SuggestTagsParams extends Equatable {
  const SuggestTagsParams({
    required this.text,
    required this.existingTags,
  });

  /// Free-form input — typically the manual-entry note or a receipt
  /// item's display name.
  final String text;

  /// Tags the caller has already accepted; we suppress duplicates.
  final List<String> existingTags;

  @override
  List<Object?> get props => <Object?>[text, existingTags];
}

/// Pure-function smart tagger.
///
/// Returns suggestions that aren't already in [existingTags]; tag matches
/// are case-insensitive. Caller decides whether to auto-apply or just
/// surface them under the tag input.
class SuggestTagsForExpenseUseCase {
  const SuggestTagsForExpenseUseCase();

  Future<Either<Failure, List<String>>> call(SuggestTagsParams params) async {
    final String haystack = params.text.toLowerCase();
    if (haystack.trim().isEmpty) {
      return const Right<Failure, List<String>>(<String>[]);
    }

    final Set<String> existing = params.existingTags
        .map((String t) => t.toLowerCase())
        .toSet();

    // Use a LinkedHashSet so we preserve "first match wins" ordering
    // and dedupe identical tags raised by multiple keywords.
    final List<String> suggestions = <String>[];
    for (final MapEntry<String, String> entry in _kKeywordToTag.entries) {
      if (!haystack.contains(entry.key)) continue;
      final String tag = entry.value;
      if (existing.contains(tag.toLowerCase())) continue;
      if (suggestions
          .any((String s) => s.toLowerCase() == tag.toLowerCase())) {
        continue;
      }
      suggestions.add(tag);
    }
    return Right<Failure, List<String>>(suggestions);
  }
}
