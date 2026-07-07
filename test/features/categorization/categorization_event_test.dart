import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';
import 'package:smartspend/features/categorization/presentation/bloc/categorization_bloc.dart';

/// Equality contracts for [CategorizationEvent] subtypes.
void main() {
  const Category category = Category(
    id: 1,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    isCustom: false,
  );

  group('CategorizationEvent equality', () {
    test('should compare CategorySuggestionRequested by all inputs', () {
      expect(
        const CategorySuggestionRequested(
          storeName: 'BİM',
          itemNames: <String>['EKMEK'],
          availableCategories: <Category>[category],
        ),
        const CategorySuggestionRequested(
          storeName: 'BİM',
          itemNames: <String>['EKMEK'],
          availableCategories: <Category>[category],
        ),
      );
      expect(
        const CategorySuggestionRequested(
          storeName: 'BİM',
          itemNames: <String>['EKMEK'],
          availableCategories: <Category>[category],
        ),
        isNot(
          const CategorySuggestionRequested(
            storeName: 'A101',
            itemNames: <String>['EKMEK'],
            availableCategories: <Category>[category],
          ),
        ),
      );
    });

    test('should compare TagSuggestionRequested by text and known tags', () {
      expect(
        const TagSuggestionRequested(
          text: 'starbucks kahve',
          existingTags: <String>['kahve'],
        ),
        const TagSuggestionRequested(
          text: 'starbucks kahve',
          existingTags: <String>['kahve'],
        ),
      );
      expect(
        const TagSuggestionRequested(
          text: 'starbucks kahve',
          existingTags: <String>[],
        ),
        isNot(
          const TagSuggestionRequested(
            text: 'starbucks kahve',
            existingTags: <String>['kahve'],
          ),
        ),
      );
    });

    test('should compare UserCorrectionRecorded by correction payload', () {
      final UserCorrection correction = UserCorrection(
        storeName: 'BİM',
        oldCategoryId: 1,
        newCategoryId: 2,
        occurredAt: DateTime.utc(2026, 7, 7),
      );
      expect(
        UserCorrectionRecorded(correction: correction),
        UserCorrectionRecorded(correction: correction),
      );
    });
  });
}
