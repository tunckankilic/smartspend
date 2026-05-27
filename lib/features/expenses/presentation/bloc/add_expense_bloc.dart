// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/create_category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_tags_for_expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/domain/usecases/add_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_all_tags.dart';
import 'package:smartspend/features/expenses/domain/usecases/update_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

part 'add_expense_event.dart';
part 'add_expense_state.dart';

/// Owns the manual-entry form (Sprint 3.2) for both **adding** a new
/// expense and **editing** an existing one.
///
/// Lifecycle:
///
/// ```text
/// AddExpenseInitial
///   → AddExpenseLoading
///   → AddExpenseReady   (steady editable state)
///   → AddExpenseSaved   (terminal — caller pops)
///   → AddExpenseFailure (recoverable; previous Ready re-emitted afterwards)
/// ```
///
/// Sprint 4 dropped the direct `CategoryDao` dependency in favour of
/// [ListCategoriesUseCase] + [CreateCategoryUseCase], which means inline
/// category creation from the picker now persists through the repository
/// just like the scan flow does.
class AddExpenseBloc extends Bloc<AddExpenseEvent, AddExpenseState> {
  AddExpenseBloc({
    required AddExpenseUseCase addExpense,
    required UpdateExpenseUseCase updateExpense,
    required GetAllTagsUseCase getAllTags,
    required ListCategoriesUseCase listCategories,
    required CreateCategoryUseCase createCategory,
    required SuggestTagsForExpenseUseCase suggestTags,
  })  : _add = addExpense,
        _update = updateExpense,
        _getAllTags = getAllTags,
        _listCategories = listCategories,
        _createCategory = createCategory,
        _suggestTags = suggestTags,
        super(const AddExpenseInitial()) {
    // Field-mutation handlers use `sequential()` because note + tag
    // changes share state (smart-tag suggestions read `tags`), and the
    // default concurrent transformer would race when the UI dispatches
    // them back-to-back (e.g. on a fast-typed note edit).
    on<AddExpenseStarted>(_onStarted);
    on<AddExpenseEditStarted>(_onEditStarted);
    on<AddExpenseAmountChanged>(_onAmount, transformer: sequential());
    on<AddExpenseCategorySelected>(
      _onCategorySelected,
      transformer: sequential(),
    );
    on<AddExpenseCategoryCreated>(
      _onCategoryCreated,
      transformer: sequential(),
    );
    on<AddExpenseDateSelected>(_onDate, transformer: sequential());
    on<AddExpenseNoteChanged>(_onNote, transformer: sequential());
    on<AddExpenseTagAdded>(_onTagAdded, transformer: sequential());
    on<AddExpenseTagRemoved>(_onTagRemoved, transformer: sequential());
    on<AddExpenseRecurringToggled>(
      _onRecurringToggled,
      transformer: sequential(),
    );
    on<AddExpensePeriodChanged>(
      _onPeriodChanged,
      transformer: sequential(),
    );
    on<AddExpenseSubmitted>(_onSubmitted);
  }

  final AddExpenseUseCase _add;
  final UpdateExpenseUseCase _update;
  final GetAllTagsUseCase _getAllTags;
  final ListCategoriesUseCase _listCategories;
  final CreateCategoryUseCase _createCategory;
  final SuggestTagsForExpenseUseCase _suggestTags;

  // ---------------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------------

  Future<void> _onStarted(
    AddExpenseStarted event,
    Emitter<AddExpenseState> emit,
  ) async {
    emit(const AddExpenseLoading());
    final (List<Category> categories, List<String> tags) = await _bootstrap();
    emit(
      AddExpenseReady(
        mode: AddExpenseMode.add,
        amountInput: '',
        amountMinor: null,
        date: DateTime.now().toUtc(),
        categories: categories,
        availableTags: tags,
        category: _guessDefaultCategory(categories),
      ),
    );
  }

  Future<void> _onEditStarted(
    AddExpenseEditStarted event,
    Emitter<AddExpenseState> emit,
  ) async {
    emit(const AddExpenseLoading());
    final (List<Category> categories, List<String> tags) = await _bootstrap();
    final Expense e = event.expense;
    emit(
      AddExpenseReady(
        mode: AddExpenseMode.edit,
        editingId: e.id,
        amountInput: (e.amount / 100).toStringAsFixed(2),
        amountMinor: e.amount,
        date: e.date,
        category: categories.firstWhere(
          (Category c) => c.id == e.category.id,
          orElse: () => e.category,
        ),
        note: e.note,
        tags: e.tags,
        isRecurring: e.isRecurring,
        recurringPeriod: e.recurringPeriod,
        categories: categories,
        availableTags: tags,
      ),
    );
  }

  Future<(List<Category>, List<String>)> _bootstrap() async {
    final Either<Failure, List<Category>> catsResult =
        await _listCategories(const ListCategoriesParams());
    final List<Category> categories =
        catsResult.getOrElse(() => const <Category>[]);

    final Either<Failure, List<String>> tagsResult =
        await _getAllTags(const NoParams());
    final List<String> tags = tagsResult.getOrElse(() => const <String>[]);
    return (categories, tags);
  }

  Category? _guessDefaultCategory(List<Category> cats) {
    if (cats.isEmpty) return null;
    return cats.firstWhere(
      (Category c) => c.icon == 'shopping_cart' ||
          c.name.toLowerCase() == 'market',
      orElse: () => cats.first,
    );
  }

  // ---------------------------------------------------------------------
  // Field updates
  // ---------------------------------------------------------------------

  void _onAmount(
    AddExpenseAmountChanged event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      final int? minor = parseMinorInput(event.input);
      return s.copyWith(
        amountInput: event.input,
        amountMinor: minor,
        clearAmountMinor: minor == null,
      );
    });
  }

  void _onCategorySelected(
    AddExpenseCategorySelected event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      return s.copyWith(category: event.category);
    });
  }

  Future<void> _onCategoryCreated(
    AddExpenseCategoryCreated event,
    Emitter<AddExpenseState> emit,
  ) async {
    final AddExpenseState current = state;
    if (current is! AddExpenseReady) return;

    final Either<Failure, Category> result = await _createCategory(
      CreateCategoryParams(
        name: event.name,
        icon: event.icon,
        color: event.color,
      ),
    );
    result.fold(
      (Failure f) {
        emit(AddExpenseFailure(failure: f));
        emit(current);
      },
      (Category created) {
        emit(
          current.copyWith(
            categories: <Category>[...current.categories, created],
            category: created,
            validationErrors: const <AddExpenseValidationError>{},
          ),
        );
      },
    );
  }

  void _onDate(
    AddExpenseDateSelected event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      return s.copyWith(date: event.date.toUtc());
    });
  }

  Future<void> _onNote(
    AddExpenseNoteChanged event,
    Emitter<AddExpenseState> emit,
  ) async {
    final AddExpenseState current = state;
    if (current is! AddExpenseReady) return;
    final String trimmed = event.note.trim();
    final List<String> suggestions = await _computeTagSuggestions(
      text: trimmed,
      existingTags: current.tags,
    );
    emit(
      current.copyWith(
        note: trimmed.isEmpty ? null : trimmed,
        clearNote: trimmed.isEmpty,
        suggestedTags: suggestions,
        validationErrors: const <AddExpenseValidationError>{},
      ),
    );
  }

  Future<void> _onTagAdded(
    AddExpenseTagAdded event,
    Emitter<AddExpenseState> emit,
  ) async {
    final AddExpenseState current = state;
    if (current is! AddExpenseReady) return;
    final String trimmed = event.tag.trim();
    if (trimmed.isEmpty) return;
    final bool exists = current.tags.any(
      (String t) => t.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) return;
    final List<String> nextTags = <String>[...current.tags, trimmed];
    final List<String> suggestions = await _computeTagSuggestions(
      text: current.note ?? '',
      existingTags: nextTags,
    );
    emit(
      current.copyWith(
        tags: nextTags,
        suggestedTags: suggestions,
        validationErrors: const <AddExpenseValidationError>{},
      ),
    );
  }

  Future<void> _onTagRemoved(
    AddExpenseTagRemoved event,
    Emitter<AddExpenseState> emit,
  ) async {
    final AddExpenseState current = state;
    if (current is! AddExpenseReady) return;
    final List<String> nextTags = <String>[...current.tags]
      ..removeWhere(
        (String t) => t.toLowerCase() == event.tag.toLowerCase(),
      );
    final List<String> suggestions = await _computeTagSuggestions(
      text: current.note ?? '',
      existingTags: nextTags,
    );
    emit(
      current.copyWith(
        tags: nextTags,
        suggestedTags: suggestions,
        validationErrors: const <AddExpenseValidationError>{},
      ),
    );
  }

  Future<List<String>> _computeTagSuggestions({
    required String text,
    required List<String> existingTags,
  }) async {
    final Either<Failure, List<String>> result = await _suggestTags(
      SuggestTagsParams(text: text, existingTags: existingTags),
    );
    return result.getOrElse(() => const <String>[]);
  }

  void _onRecurringToggled(
    AddExpenseRecurringToggled event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      if (!event.value) {
        return s.copyWith(
          isRecurring: false,
          recurringPeriod: null,
          clearRecurringPeriod: true,
        );
      }
      return s.copyWith(
        isRecurring: true,
        recurringPeriod: s.recurringPeriod ?? RecurringPeriod.monthly,
      );
    });
  }

  void _onPeriodChanged(
    AddExpensePeriodChanged event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      return s.copyWith(
        recurringPeriod: event.period,
        isRecurring: true,
      );
    });
  }

  // ---------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------

  Future<void> _onSubmitted(
    AddExpenseSubmitted event,
    Emitter<AddExpenseState> emit,
  ) async {
    final AddExpenseState current = state;
    if (current is! AddExpenseReady) return;
    if (current.isSubmitting) return;

    final Set<AddExpenseValidationError> errors = _validate(current);
    if (errors.isNotEmpty) {
      emit(current.copyWith(validationErrors: errors));
      return;
    }

    emit(
      current.copyWith(
        isSubmitting: true,
        validationErrors: const <AddExpenseValidationError>{},
      ),
    );

    final int amount = current.amountMinor!;
    final int categoryId = current.category!.id;

    if (current.mode == AddExpenseMode.add) {
      final Either<Failure, int> r = await _add(
        AddExpenseParams(
          amount: amount,
          categoryId: categoryId,
          date: current.date,
          note: current.note,
          isRecurring: current.isRecurring,
          recurringPeriod:
              current.isRecurring ? current.recurringPeriod : null,
          tags: current.tags,
        ),
      );
      r.fold(
        (Failure f) {
          emit(AddExpenseFailure(failure: f));
          emit(current.copyWith(isSubmitting: false));
        },
        (int id) => emit(AddExpenseSaved(savedId: id)),
      );
      return;
    }

    // Edit branch
    final int id = current.editingId!;
    final Either<Failure, void> r = await _update(
      UpdateExpenseParams(
        id: id,
        amount: amount,
        categoryId: categoryId,
        date: current.date,
        note: current.note,
        clearNote: current.note == null,
        isRecurring: current.isRecurring,
        recurringPeriod:
            current.isRecurring ? current.recurringPeriod : null,
        clearRecurringPeriod: !current.isRecurring,
        tags: current.tags,
      ),
    );
    r.fold(
      (Failure f) {
        emit(AddExpenseFailure(failure: f));
        emit(current.copyWith(isSubmitting: false));
      },
      (_) => emit(AddExpenseSaved(savedId: id)),
    );
  }

  Set<AddExpenseValidationError> _validate(AddExpenseReady s) {
    final Set<AddExpenseValidationError> errors =
        <AddExpenseValidationError>{};
    if (s.amountMinor == null || s.amountMinor! <= 0) {
      errors.add(AddExpenseValidationError.invalidAmount);
    }
    if (s.category == null) {
      errors.add(AddExpenseValidationError.missingCategory);
    }
    if (s.date.isAfter(DateTime.now().toUtc())) {
      errors.add(AddExpenseValidationError.futureDate);
    }
    if (s.isRecurring && s.recurringPeriod == null) {
      errors.add(AddExpenseValidationError.missingRecurringPeriod);
    }
    return errors;
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  void _mutate(
    Emitter<AddExpenseState> emit,
    AddExpenseReady Function(AddExpenseReady) f,
  ) {
    final AddExpenseState current = state;
    if (current is! AddExpenseReady) return;
    emit(
      f(current).copyWith(
        validationErrors: const <AddExpenseValidationError>{},
      ),
    );
  }
}
