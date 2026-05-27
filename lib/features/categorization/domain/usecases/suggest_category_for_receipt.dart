import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/engines/categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';

class SuggestCategoryParams extends Equatable {
  const SuggestCategoryParams({
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

/// Picks the best category guess for an OCR'd receipt.
class SuggestCategoryForReceiptUseCase {
  const SuggestCategoryForReceiptUseCase(this._engine);

  final CategorizationEngine _engine;

  Future<Either<Failure, CategorizationSuggestion>> call(
    SuggestCategoryParams params,
  ) async {
    try {
      final CategorizationSuggestion s = await _engine.suggest(
        storeName: params.storeName,
        itemNames: params.itemNames,
        availableCategories: params.availableCategories,
      );
      return Right<Failure, CategorizationSuggestion>(s);
    } on Exception catch (e) {
      return Left<Failure, CategorizationSuggestion>(
        UnexpectedFailure(message: 'suggestCategory failed: $e'),
      );
    }
  }
}
