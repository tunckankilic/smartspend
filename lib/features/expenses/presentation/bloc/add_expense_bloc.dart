// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/database/daos/category_dao.dart';
import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
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
/// The category list comes straight from [CategoryDao] for now — Sprint
/// 4 will wrap that in a Categories repository when the AI categorizer
/// feature gets its own bloc. Pulling the dao directly here is the only
/// presentation-layer DAO call in the codebase; revisit once we have a
/// dedicated repository to avoid leaking Drift types upward.
class AddExpenseBloc extends Bloc<AddExpenseEvent, AddExpenseState> {
  AddExpenseBloc({
    required AddExpenseUseCase addExpense,
    required UpdateExpenseUseCase updateExpense,
    required GetAllTagsUseCase getAllTags,
    required CategoryDao categoryDao,
  })  : _add = addExpense,
        _update = updateExpense,
        _getAllTags = getAllTags,
        _categoryDao = categoryDao,
        super(const AddExpenseInitial()) {
    on<AddExpenseStarted>(_onStarted);
    on<AddExpenseEditStarted>(_onEditStarted);
    on<AddExpenseAmountChanged>(_onAmount);
    on<AddExpenseCategorySelected>(_onCategorySelected);
    on<AddExpenseCategoryCreated>(_onCategoryCreated);
    on<AddExpenseDateSelected>(_onDate);
    on<AddExpenseNoteChanged>(_onNote);
    on<AddExpenseTagAdded>(_onTagAdded);
    on<AddExpenseTagRemoved>(_onTagRemoved);
    on<AddExpenseRecurringToggled>(_onRecurringToggled);
    on<AddExpensePeriodChanged>(_onPeriodChanged);
    on<AddExpenseSubmitted>(_onSubmitted);
  }

  final AddExpenseUseCase _add;
  final UpdateExpenseUseCase _update;
  final GetAllTagsUseCase _getAllTags;
  final CategoryDao _categoryDao;

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
    final List<drift_db.Category> rows = await _categoryDao.getAll();
    final List<Category> categories = rows
        .map(
          (drift_db.Category c) => Category(
            id: c.id,
            name: c.name,
            icon: c.icon,
            color: c.color,
            isCustom: c.isCustom,
          ),
        )
        .toList(growable: false);

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

  void _onCategoryCreated(
    AddExpenseCategoryCreated event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      return s.copyWith(
        categories: <Category>[...s.categories, event.category],
        category: event.category,
      );
    });
  }

  void _onDate(
    AddExpenseDateSelected event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      return s.copyWith(date: event.date.toUtc());
    });
  }

  void _onNote(
    AddExpenseNoteChanged event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      final String trimmed = event.note.trim();
      return s.copyWith(
        note: trimmed.isEmpty ? null : trimmed,
        clearNote: trimmed.isEmpty,
      );
    });
  }

  void _onTagAdded(
    AddExpenseTagAdded event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      final String trimmed = event.tag.trim();
      if (trimmed.isEmpty) return s;
      // Case-insensitive de-dupe, preserve display casing of first occurrence.
      final bool exists = s.tags.any(
        (String t) => t.toLowerCase() == trimmed.toLowerCase(),
      );
      if (exists) return s;
      return s.copyWith(tags: <String>[...s.tags, trimmed]);
    });
  }

  void _onTagRemoved(
    AddExpenseTagRemoved event,
    Emitter<AddExpenseState> emit,
  ) {
    _mutate(emit, (AddExpenseReady s) {
      final List<String> next = <String>[...s.tags]
        ..removeWhere(
          (String t) => t.toLowerCase() == event.tag.toLowerCase(),
        );
      return s.copyWith(tags: next);
    });
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
