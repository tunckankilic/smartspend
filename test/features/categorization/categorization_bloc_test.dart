import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';
import 'package:smartspend/features/categorization/domain/usecases/record_user_correction.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_category_for_receipt.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_tags_for_expense.dart';
import 'package:smartspend/features/categorization/presentation/bloc/categorization_bloc.dart';

class _MockSuggestCategory extends Mock
    implements SuggestCategoryForReceiptUseCase {}

class _MockSuggestTags extends Mock implements SuggestTagsForExpenseUseCase {}

class _MockRecordCorrection extends Mock
    implements RecordUserCorrectionUseCase {}

void main() {
  late _MockSuggestCategory suggestCategory;
  late _MockSuggestTags suggestTags;
  late _MockRecordCorrection recordCorrection;

  const Category category = Category(
    id: 5,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF000000,
    isCustom: false,
  );
  const CategorizationSuggestion suggestion = CategorizationSuggestion(
    category: category,
    confidence: 0.9,
    source: CategorizationSource.keywordStore,
  );

  setUpAll(() {
    registerFallbackValue(
      const SuggestCategoryParams(
        storeName: null,
        itemNames: <String>[],
        availableCategories: <Category>[],
      ),
    );
    registerFallbackValue(
      const SuggestTagsParams(text: '', existingTags: <String>[]),
    );
    registerFallbackValue(
      RecordUserCorrectionParams(
        correction: UserCorrection(
          storeName: 'x',
          oldCategoryId: null,
          newCategoryId: 1,
          occurredAt: DateTime.utc(2026),
        ),
      ),
    );
  });

  setUp(() {
    suggestCategory = _MockSuggestCategory();
    suggestTags = _MockSuggestTags();
    recordCorrection = _MockRecordCorrection();
  });

  CategorizationBloc build() => CategorizationBloc(
        suggestCategory: suggestCategory,
        suggestTags: suggestTags,
        recordCorrection: recordCorrection,
      );

  blocTest<CategorizationBloc, CategorizationState>(
    'should emit [Loading, CategorySuggestionReady] on a successful '
    'category request',
    build: () {
      when(() => suggestCategory(any())).thenAnswer(
        (_) async =>
            const Right<Failure, CategorizationSuggestion>(suggestion),
      );
      return build();
    },
    act: (CategorizationBloc bloc) => bloc.add(
      const CategorySuggestionRequested(
        storeName: 'BİM',
        itemNames: <String>['ekmek'],
        availableCategories: <Category>[category],
      ),
    ),
    expect: () => const <CategorizationState>[
      CategorizationLoading(),
      CategorySuggestionReady(suggestion: suggestion),
    ],
  );

  blocTest<CategorizationBloc, CategorizationState>(
    'should emit [Loading, Failure] when the category usecase fails',
    build: () {
      when(() => suggestCategory(any())).thenAnswer(
        (_) async => const Left<Failure, CategorizationSuggestion>(
          CacheFailure(message: 'no engine'),
        ),
      );
      return build();
    },
    act: (CategorizationBloc bloc) => bloc.add(
      const CategorySuggestionRequested(
        storeName: 'BİM',
        itemNames: <String>[],
        availableCategories: <Category>[category],
      ),
    ),
    expect: () => <CategorizationState>[
      const CategorizationLoading(),
      const CategorizationFailure(
        failure: CacheFailure(message: 'no engine'),
      ),
    ],
  );

  blocTest<CategorizationBloc, CategorizationState>(
    'should emit TagSuggestionReady on a successful tag request',
    build: () {
      when(() => suggestTags(any())).thenAnswer(
        (_) async => const Right<Failure, List<String>>(<String>['iş']),
      );
      return build();
    },
    act: (CategorizationBloc bloc) => bloc.add(
      const TagSuggestionRequested(text: 'iş yemeği', existingTags: <String>[]),
    ),
    expect: () => const <CategorizationState>[
      TagSuggestionReady(tags: <String>['iş']),
    ],
  );

  blocTest<CategorizationBloc, CategorizationState>(
    'should emit Failure when the tag usecase fails',
    build: () {
      when(() => suggestTags(any())).thenAnswer(
        (_) async => const Left<Failure, List<String>>(
          CacheFailure(message: 'boom'),
        ),
      );
      return build();
    },
    act: (CategorizationBloc bloc) => bloc.add(
      const TagSuggestionRequested(text: 'x', existingTags: <String>[]),
    ),
    expect: () => <CategorizationState>[
      const CategorizationFailure(failure: CacheFailure(message: 'boom')),
    ],
  );

  blocTest<CategorizationBloc, CategorizationState>(
    'should forward a recorded correction to the usecase without emitting',
    build: () {
      when(() => recordCorrection(any()))
          .thenAnswer((_) async => const Right<Failure, void>(null));
      return build();
    },
    act: (CategorizationBloc bloc) => bloc.add(
      UserCorrectionRecorded(
        correction: UserCorrection(
          storeName: 'BİM',
          oldCategoryId: 3,
          newCategoryId: 5,
          occurredAt: DateTime.utc(2026, 5, 1),
        ),
      ),
    ),
    expect: () => const <CategorizationState>[],
    verify: (_) => verify(() => recordCorrection(any())).called(1),
  );
}
