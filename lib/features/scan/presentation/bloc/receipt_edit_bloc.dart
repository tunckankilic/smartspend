// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_category_for_receipt.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';

part 'receipt_edit_event.dart';
part 'receipt_edit_state.dart';

/// Reasons a receipt isn't ready to save. The UI translates each value
/// into a localized message.
enum ReceiptEditValidationError {
  /// No items left — at least one is required.
  emptyItems,

  /// Computed total is zero or negative.
  nonPositiveTotal,

  /// Receipt date is in the future.
  futureDate,

  /// User hasn't picked a default category yet.
  missingDefaultCategory,
}

/// Owns the editable view of a [ScannedReceipt].
///
/// Lifecycle:
///
/// ```text
/// ReceiptEditInitial
///   → ReceiptEditReady   (categories loaded, receipt seeded from OCR)
///   → ReceiptEditSaving  (persistence running)
///   → ReceiptEditSaved   (terminal — caller should pop and route to /expenses)
///   → ReceiptEditFailure (recoverable error; ready state is preserved)
/// ```
class ReceiptEditBloc extends Bloc<ReceiptEditEvent, ReceiptEditState> {
  ReceiptEditBloc({
    required ScanRepository repository,
    required SuggestCategoryForReceiptUseCase suggestCategory,
  })  : _repository = repository,
        _suggestCategory = suggestCategory,
        super(const ReceiptEditInitial()) {
    on<ReceiptEditStarted>(_onStarted);
    on<ReceiptStoreNameChanged>(_onStoreName);
    on<ReceiptDateChanged>(_onDate);
    on<ReceiptCurrencyChanged>(_onCurrency);
    on<ReceiptDefaultCategoryChanged>(_onDefaultCategory);
    on<ReceiptItemAdded>(_onItemAdded);
    on<ReceiptItemRemoved>(_onItemRemoved);
    on<ReceiptItemUpdated>(_onItemUpdated);
    on<ReceiptItemCategoryChanged>(_onItemCategory);
    on<ReceiptCategoryCreated>(_onCategoryCreated);
    on<ReceiptEditSubmitted>(_onSubmitted);
  }

  final ScanRepository _repository;
  final SuggestCategoryForReceiptUseCase _suggestCategory;

  // ---------------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------------

  Future<void> _onStarted(
    ReceiptEditStarted event,
    Emitter<ReceiptEditState> emit,
  ) async {
    emit(const ReceiptEditInitial());
    final Either<Failure, List<Category>> result =
        await _repository.listCategories();
    await result.fold<Future<void>>(
      (Failure f) async => emit(ReceiptEditFailure(failure: f)),
      (List<Category> cats) async {
        final ScannedReceipt seeded = _ensureAtLeastOneItem(event.receipt);
        final int? guessed =
            await _guessDefaultCategory(seeded, cats);
        emit(
          ReceiptEditReady(
            receipt: seeded,
            categories: cats,
            defaultCategoryId: guessed,
          ),
        );
      },
    );
  }

  ScannedReceipt _ensureAtLeastOneItem(ScannedReceipt receipt) {
    if (receipt.items.isNotEmpty) return receipt;
    return receipt.copyWith(items: <ScannedItem>[ScannedItem.empty()]);
  }

  /// Hybrid pipeline:
  /// 1. Ask [CategorizationEngine] for a guess based on store + items.
  /// 2. Fall back to the user's "Market" / first-available category if
  ///    the engine returns no usable match.
  Future<int?> _guessDefaultCategory(
    ScannedReceipt receipt,
    List<Category> cats,
  ) async {
    if (cats.isEmpty) return null;

    final Either<Failure, CategorizationSuggestion> result =
        await _suggestCategory(
      SuggestCategoryParams(
        storeName: receipt.storeName,
        itemNames: receipt.items
            .map((ScannedItem i) => i.name)
            .where((String n) => n.trim().isNotEmpty)
            .toList(growable: false),
        availableCategories: cats,
      ),
    );
    final CategorizationSuggestion suggestion =
        result.getOrElse(() => const CategorizationSuggestion.none());
    if (suggestion.hasMatch) return suggestion.category!.id;

    // Fallback: keep the Sprint 2 default so an offline / empty-store
    // receipt is still saveable in one tap.
    final Category fallback = cats.firstWhere(
      (Category c) =>
          c.icon == 'shopping_cart' || c.name.toLowerCase() == 'market',
      orElse: () => cats.first,
    );
    return fallback.id;
  }

  // ---------------------------------------------------------------------
  // Field updates
  // ---------------------------------------------------------------------

  void _onStoreName(
    ReceiptStoreNameChanged event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      final String? trimmed =
          event.storeName.trim().isEmpty ? null : event.storeName.trim();
      return s.copyWith(receipt: s.receipt.copyWith(storeName: trimmed));
    });
  }

  void _onDate(
    ReceiptDateChanged event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      return s.copyWith(receipt: s.receipt.copyWith(date: event.date));
    });
  }

  void _onCurrency(
    ReceiptCurrencyChanged event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      return s.copyWith(receipt: s.receipt.copyWith(currency: event.currency));
    });
  }

  void _onDefaultCategory(
    ReceiptDefaultCategoryChanged event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      return s.copyWith(defaultCategoryId: event.categoryId);
    });
  }

  // ---------------------------------------------------------------------
  // Item updates
  // ---------------------------------------------------------------------

  void _onItemAdded(
    ReceiptItemAdded event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      final List<ScannedItem> items = <ScannedItem>[
        ...s.receipt.items,
        ScannedItem.empty(),
      ];
      return s.copyWith(receipt: s.receipt.copyWith(items: items));
    });
  }

  void _onItemRemoved(
    ReceiptItemRemoved event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      if (event.index < 0 || event.index >= s.receipt.items.length) return s;
      final List<ScannedItem> items = <ScannedItem>[...s.receipt.items]
        ..removeAt(event.index);
      return s.copyWith(receipt: s.receipt.copyWith(items: items));
    });
  }

  void _onItemUpdated(
    ReceiptItemUpdated event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      if (event.index < 0 || event.index >= s.receipt.items.length) return s;
      final List<ScannedItem> items = <ScannedItem>[...s.receipt.items];
      items[event.index] = event.item;
      return s.copyWith(receipt: s.receipt.copyWith(items: items));
    });
  }

  void _onItemCategory(
    ReceiptItemCategoryChanged event,
    Emitter<ReceiptEditState> emit,
  ) {
    _mutate(emit, (ReceiptEditReady s) {
      if (event.index < 0 || event.index >= s.receipt.items.length) return s;
      final List<ScannedItem> items = <ScannedItem>[...s.receipt.items];
      items[event.index] = items[event.index].copyWith(
        categoryId: event.categoryId,
        clearCategory: event.categoryId == null,
      );
      return s.copyWith(receipt: s.receipt.copyWith(items: items));
    });
  }

  Future<void> _onCategoryCreated(
    ReceiptCategoryCreated event,
    Emitter<ReceiptEditState> emit,
  ) async {
    final ReceiptEditState current = state;
    if (current is! ReceiptEditReady) return;

    final Either<Failure, Category> result =
        await _repository.createCategory(
      name: event.name,
      icon: event.icon,
      color: event.color,
    );

    result.fold(
      (Failure f) => emit(ReceiptEditFailure(failure: f)),
      (Category created) {
        emit(
          current.copyWith(
            categories: <Category>[...current.categories, created],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------

  Future<void> _onSubmitted(
    ReceiptEditSubmitted event,
    Emitter<ReceiptEditState> emit,
  ) async {
    final ReceiptEditState current = state;
    if (current is! ReceiptEditReady) return;

    final Set<ReceiptEditValidationError> errors = _validate(current);
    if (errors.isNotEmpty) {
      emit(current.copyWith(validationErrors: errors));
      return;
    }

    final int? defaultCategoryId = current.defaultCategoryId;
    if (defaultCategoryId == null) {
      emit(
        current.copyWith(
          validationErrors: <ReceiptEditValidationError>{
            ReceiptEditValidationError.missingDefaultCategory,
          },
        ),
      );
      return;
    }

    emit(ReceiptEditSaving(receipt: current.receipt));
    final Either<Failure, int> result = await _repository.saveReceipt(
      receipt: _withRecomputedTotal(current.receipt),
      defaultCategoryId: defaultCategoryId,
    );
    result.fold(
      (Failure f) {
        emit(ReceiptEditFailure(failure: f));
        emit(current);
      },
      (int receiptId) => emit(ReceiptEditSaved(receiptId: receiptId)),
    );
  }

  Set<ReceiptEditValidationError> _validate(ReceiptEditReady s) {
    final Set<ReceiptEditValidationError> errors =
        <ReceiptEditValidationError>{};
    final List<ScannedItem> valid = s.receipt.items
        .where((ScannedItem i) => i.name.trim().isNotEmpty && i.totalPrice > 0)
        .toList(growable: false);
    if (valid.isEmpty) errors.add(ReceiptEditValidationError.emptyItems);

    final int computed = computeTotal(s.receipt.items);
    if (computed <= 0) errors.add(ReceiptEditValidationError.nonPositiveTotal);

    final DateTime? date = s.receipt.date;
    if (date != null && date.isAfter(DateTime.now().toUtc())) {
      errors.add(ReceiptEditValidationError.futureDate);
    }
    return errors;
  }

  ScannedReceipt _withRecomputedTotal(ScannedReceipt r) {
    final List<ScannedItem> valid = r.items
        .where((ScannedItem i) => i.name.trim().isNotEmpty && i.totalPrice > 0)
        .toList(growable: false);
    return r.copyWith(
      items: valid,
      total: computeTotal(valid),
    );
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  void _mutate(
    Emitter<ReceiptEditState> emit,
    ReceiptEditReady Function(ReceiptEditReady) f,
  ) {
    final ReceiptEditState current = state;
    if (current is! ReceiptEditReady) return;
    final ReceiptEditReady next = f(current).copyWith(
      validationErrors: const <ReceiptEditValidationError>{},
    );
    emit(next);
  }

  /// Sum of valid line items' `totalPrice`. Public so the UI can render
  /// the live total under the items list.
  static int computeTotal(List<ScannedItem> items) {
    int sum = 0;
    for (final ScannedItem item in items) {
      if (item.totalPrice > 0) sum += item.totalPrice;
    }
    return sum;
  }
}
