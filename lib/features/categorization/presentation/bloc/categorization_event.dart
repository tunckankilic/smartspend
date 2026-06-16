part of 'categorization_bloc.dart';

sealed class CategorizationEvent extends Equatable {
  const CategorizationEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Ask the engine to categorize a receipt. Caller passes the latest
/// `availableCategories` so the engine never returns a stale or
/// unknown id.
final class CategorySuggestionRequested extends CategorizationEvent {
  const CategorySuggestionRequested({
    required this.storeName,
    required this.itemNames,
    required this.availableCategories,
  });

  final String? storeName;
  final List<String> itemNames;
  final List<Category> availableCategories;

  @override
  List<Object?> get props =>
      <Object?>[storeName, itemNames, availableCategories];
}

/// Ask the engine for smart tag suggestions from free-form text.
final class TagSuggestionRequested extends CategorizationEvent {
  const TagSuggestionRequested({
    required this.text,
    required this.existingTags,
  });

  final String text;
  final List<String> existingTags;

  @override
  List<Object?> get props => <Object?>[text, existingTags];
}

/// Tell the engine the user overrode a previous suggestion.
final class UserCorrectionRecorded extends CategorizationEvent {
  const UserCorrectionRecorded({required this.correction});

  final UserCorrection correction;

  @override
  List<Object?> get props => <Object?>[correction];
}
