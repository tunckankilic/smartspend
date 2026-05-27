part of 'receipt_edit_bloc.dart';

/// Observable outputs of [ReceiptEditBloc].
sealed class ReceiptEditState extends Equatable {
  const ReceiptEditState();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Loading categories from Drift.
final class ReceiptEditInitial extends ReceiptEditState {
  const ReceiptEditInitial();
}

/// User-facing edit state.
final class ReceiptEditReady extends ReceiptEditState {
  const ReceiptEditReady({
    required this.receipt,
    required this.categories,
    this.defaultCategoryId,
    this.validationErrors = const <ReceiptEditValidationError>{},
  });

  final ScannedReceipt receipt;
  final List<ScanCategory> categories;

  /// Category applied to items the user hasn't manually tagged. `null`
  /// blocks Save and surfaces a validation chip.
  final int? defaultCategoryId;

  /// Validation errors surfaced after a failed Save attempt. Empty in
  /// the happy path; cleared on the next field edit.
  final Set<ReceiptEditValidationError> validationErrors;

  ReceiptEditReady copyWith({
    ScannedReceipt? receipt,
    List<ScanCategory>? categories,
    int? defaultCategoryId,
    Set<ReceiptEditValidationError>? validationErrors,
  }) {
    return ReceiptEditReady(
      receipt: receipt ?? this.receipt,
      categories: categories ?? this.categories,
      defaultCategoryId: defaultCategoryId ?? this.defaultCategoryId,
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    receipt,
    categories,
    defaultCategoryId,
    validationErrors,
  ];
}

/// Persistence in flight — UI shows a spinner and disables buttons.
final class ReceiptEditSaving extends ReceiptEditState {
  const ReceiptEditSaving({required this.receipt});

  final ScannedReceipt receipt;

  @override
  List<Object?> get props => <Object?>[receipt];
}

/// Terminal success — caller should pop and navigate to `/expenses`.
final class ReceiptEditSaved extends ReceiptEditState {
  const ReceiptEditSaved({required this.receiptId});

  /// Local Drift PK of the persisted receipt.
  final int receiptId;

  @override
  List<Object?> get props => <Object?>[receiptId];
}

/// Recoverable error. Bloc immediately re-emits the previous Ready state
/// so the UI stays interactive; this transient banner is just for
/// feedback.
final class ReceiptEditFailure extends ReceiptEditState {
  const ReceiptEditFailure({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
