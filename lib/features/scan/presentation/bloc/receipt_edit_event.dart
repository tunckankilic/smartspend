part of 'receipt_edit_bloc.dart';

/// Inputs to [ReceiptEditBloc].
sealed class ReceiptEditEvent extends Equatable {
  const ReceiptEditEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Fired once when the edit page opens. Carries the OCR-parsed receipt.
final class ReceiptEditStarted extends ReceiptEditEvent {
  const ReceiptEditStarted({required this.receipt});

  final ScannedReceipt receipt;

  @override
  List<Object?> get props => <Object?>[receipt];
}

final class ReceiptStoreNameChanged extends ReceiptEditEvent {
  const ReceiptStoreNameChanged({required this.storeName});

  final String storeName;

  @override
  List<Object?> get props => <Object?>[storeName];
}

final class ReceiptDateChanged extends ReceiptEditEvent {
  const ReceiptDateChanged({required this.date});

  final DateTime date;

  @override
  List<Object?> get props => <Object?>[date];
}

final class ReceiptCurrencyChanged extends ReceiptEditEvent {
  const ReceiptCurrencyChanged({required this.currency});

  final String currency;

  @override
  List<Object?> get props => <Object?>[currency];
}

final class ReceiptDefaultCategoryChanged extends ReceiptEditEvent {
  const ReceiptDefaultCategoryChanged({required this.categoryId});

  final int categoryId;

  @override
  List<Object?> get props => <Object?>[categoryId];
}

final class ReceiptItemAdded extends ReceiptEditEvent {
  const ReceiptItemAdded();
}

final class ReceiptItemRemoved extends ReceiptEditEvent {
  const ReceiptItemRemoved({required this.index});

  final int index;

  @override
  List<Object?> get props => <Object?>[index];
}

final class ReceiptItemUpdated extends ReceiptEditEvent {
  const ReceiptItemUpdated({required this.index, required this.item});

  final int index;
  final ScannedItem item;

  @override
  List<Object?> get props => <Object?>[index, item];
}

final class ReceiptItemCategoryChanged extends ReceiptEditEvent {
  const ReceiptItemCategoryChanged({
    required this.index,
    required this.categoryId,
  });

  final int index;
  final int? categoryId;

  @override
  List<Object?> get props => <Object?>[index, categoryId];
}

final class ReceiptCategoryCreated extends ReceiptEditEvent {
  const ReceiptCategoryCreated({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final int color;

  @override
  List<Object?> get props => <Object?>[name, icon, color];
}

/// User pressed Save. Bloc runs validation, then persists.
final class ReceiptEditSubmitted extends ReceiptEditEvent {
  const ReceiptEditSubmitted();
}
