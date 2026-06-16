// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';
import 'package:smartspend/features/categorization/domain/usecases/record_user_correction.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_category_for_receipt.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_tags_for_expense.dart';

part 'categorization_event.dart';
part 'categorization_state.dart';

/// Stand-alone bloc that other features (Scan, AddExpense) ask for
/// category + tag suggestions. Kept independent of those features so
/// the dashboard can later consume the same suggestions without
/// dragging Scan/Expense state along.
class CategorizationBloc
    extends Bloc<CategorizationEvent, CategorizationState> {
  CategorizationBloc({
    required SuggestCategoryForReceiptUseCase suggestCategory,
    required SuggestTagsForExpenseUseCase suggestTags,
    required RecordUserCorrectionUseCase recordCorrection,
  })  : _suggestCategory = suggestCategory,
        _suggestTags = suggestTags,
        _recordCorrection = recordCorrection,
        super(const CategorizationInitial()) {
    on<CategorySuggestionRequested>(_onCategoryRequested);
    on<TagSuggestionRequested>(_onTagRequested);
    on<UserCorrectionRecorded>(_onCorrection);
  }

  final SuggestCategoryForReceiptUseCase _suggestCategory;
  final SuggestTagsForExpenseUseCase _suggestTags;
  final RecordUserCorrectionUseCase _recordCorrection;

  Future<void> _onCategoryRequested(
    CategorySuggestionRequested event,
    Emitter<CategorizationState> emit,
  ) async {
    emit(const CategorizationLoading());
    final Either<Failure, CategorizationSuggestion> result =
        await _suggestCategory(
      SuggestCategoryParams(
        storeName: event.storeName,
        itemNames: event.itemNames,
        availableCategories: event.availableCategories,
      ),
    );
    result.fold(
      (Failure f) => emit(CategorizationFailure(failure: f)),
      (CategorizationSuggestion s) =>
          emit(CategorySuggestionReady(suggestion: s)),
    );
  }

  Future<void> _onTagRequested(
    TagSuggestionRequested event,
    Emitter<CategorizationState> emit,
  ) async {
    final Either<Failure, List<String>> result = await _suggestTags(
      SuggestTagsParams(text: event.text, existingTags: event.existingTags),
    );
    result.fold(
      (Failure f) => emit(CategorizationFailure(failure: f)),
      (List<String> tags) => emit(TagSuggestionReady(tags: tags)),
    );
  }

  Future<void> _onCorrection(
    UserCorrectionRecorded event,
    Emitter<CategorizationState> emit,
  ) async {
    await _recordCorrection(
      RecordUserCorrectionParams(correction: event.correction),
    );
  }
}
