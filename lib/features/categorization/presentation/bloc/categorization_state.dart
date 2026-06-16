part of 'categorization_bloc.dart';

sealed class CategorizationState extends Equatable {
  const CategorizationState();

  @override
  List<Object?> get props => const <Object?>[];
}

final class CategorizationInitial extends CategorizationState {
  const CategorizationInitial();
}

final class CategorizationLoading extends CategorizationState {
  const CategorizationLoading();
}

final class CategorySuggestionReady extends CategorizationState {
  const CategorySuggestionReady({required this.suggestion});

  final CategorizationSuggestion suggestion;

  @override
  List<Object?> get props => <Object?>[suggestion];
}

final class TagSuggestionReady extends CategorizationState {
  const TagSuggestionReady({required this.tags});

  final List<String> tags;

  @override
  List<Object?> get props => <Object?>[tags];
}

final class CategorizationFailure extends CategorizationState {
  const CategorizationFailure({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
