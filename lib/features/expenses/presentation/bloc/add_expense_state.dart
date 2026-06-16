part of 'add_expense_bloc.dart';

/// Reasons the form isn't ready to save. The UI maps each value to a
/// localized inline message.
enum AddExpenseValidationError {
  /// Amount is zero / negative / unparseable.
  invalidAmount,

  /// No category picked.
  missingCategory,

  /// Date is in the future.
  futureDate,

  /// Recurring toggle on but no period chosen.
  missingRecurringPeriod,
}

sealed class AddExpenseState extends Equatable {
  const AddExpenseState();

  @override
  List<Object?> get props => const <Object?>[];
}

final class AddExpenseInitial extends AddExpenseState {
  const AddExpenseInitial();
}

/// Loading categories + previously-used tags.
final class AddExpenseLoading extends AddExpenseState {
  const AddExpenseLoading();
}

/// Steady editable state — the bulk of the form's lifetime is here.
final class AddExpenseReady extends AddExpenseState {
  const AddExpenseReady({
    required this.mode,
    required this.amountInput,
    required this.amountMinor,
    required this.date,
    required this.categories,
    required this.availableTags,
    this.editingId,
    this.category,
    this.note,
    this.tags = const <String>[],
    this.isRecurring = false,
    this.recurringPeriod,
    this.validationErrors = const <AddExpenseValidationError>{},
    this.isSubmitting = false,
    this.suggestedTags = const <String>[],
  });

  /// Whether the user is adding a brand-new row or editing an existing
  /// one. The UI swaps the button label / app bar title accordingly.
  final AddExpenseMode mode;

  /// Local Drift PK — only set when [mode] is [AddExpenseMode.edit].
  final int? editingId;

  /// Raw text the user typed. Kept so the [TextField] controller stays
  /// in sync with the bloc.
  final String amountInput;

  /// Parsed amount in minor units. Zero (or null until parsed) means
  /// "invalid"; validation surfaces an inline error.
  final int? amountMinor;

  final Category? category;
  final DateTime date;
  final String? note;
  final List<String> tags;
  final bool isRecurring;
  final RecurringPeriod? recurringPeriod;

  /// Latest snapshot from the repository. Refreshed when the user
  /// inline-creates a new category.
  final List<Category> categories;

  /// Tag names the user has typed before — feeds the chip
  /// autocomplete suggestions.
  final List<String> availableTags;

  final Set<AddExpenseValidationError> validationErrors;

  /// `true` while the use case is running.
  final bool isSubmitting;

  /// Smart-tag hints derived from the current [note]; surfaced as
  /// quick-add chips in the [TagInput] widget. Deduped against [tags]
  /// so the user never sees a suggestion for a tag they already have.
  final List<String> suggestedTags;

  AddExpenseReady copyWith({
    AddExpenseMode? mode,
    int? editingId,
    String? amountInput,
    int? amountMinor,
    Category? category,
    DateTime? date,
    String? note,
    List<String>? tags,
    bool? isRecurring,
    RecurringPeriod? recurringPeriod,
    List<Category>? categories,
    List<String>? availableTags,
    Set<AddExpenseValidationError>? validationErrors,
    bool? isSubmitting,
    List<String>? suggestedTags,
    bool clearCategory = false,
    bool clearNote = false,
    bool clearRecurringPeriod = false,
    bool clearAmountMinor = false,
  }) {
    return AddExpenseReady(
      mode: mode ?? this.mode,
      editingId: editingId ?? this.editingId,
      amountInput: amountInput ?? this.amountInput,
      amountMinor: clearAmountMinor ? null : (amountMinor ?? this.amountMinor),
      category: clearCategory ? null : (category ?? this.category),
      date: date ?? this.date,
      note: clearNote ? null : (note ?? this.note),
      tags: tags ?? this.tags,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringPeriod: clearRecurringPeriod
          ? null
          : (recurringPeriod ?? this.recurringPeriod),
      categories: categories ?? this.categories,
      availableTags: availableTags ?? this.availableTags,
      validationErrors: validationErrors ?? this.validationErrors,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      suggestedTags: suggestedTags ?? this.suggestedTags,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    mode,
    editingId,
    amountInput,
    amountMinor,
    category,
    date,
    note,
    tags,
    isRecurring,
    recurringPeriod,
    categories,
    availableTags,
    validationErrors,
    isSubmitting,
    suggestedTags,
  ];
}

/// Terminal success — caller should pop. [savedId] is the local Drift
/// PK of the persisted row (same id in edit mode, fresh id in add).
final class AddExpenseSaved extends AddExpenseState {
  const AddExpenseSaved({required this.savedId});

  final int savedId;

  @override
  List<Object?> get props => <Object?>[savedId];
}

/// Recoverable failure — UI shows a snackbar, ready state is preserved.
final class AddExpenseFailure extends AddExpenseState {
  const AddExpenseFailure({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

enum AddExpenseMode { add, edit }
