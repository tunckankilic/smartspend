part of 'receipt_detail_bloc.dart';

sealed class ReceiptDetailEvent extends Equatable {
  const ReceiptDetailEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class ReceiptDetailLoaded extends ReceiptDetailEvent {
  const ReceiptDetailLoaded({required this.receiptId});

  final int receiptId;

  @override
  List<Object?> get props => <Object?>[receiptId];
}

/// User picked a new warranty end date (or cleared it via `null`).
final class ReceiptWarrantyChanged extends ReceiptDetailEvent {
  const ReceiptWarrantyChanged({required this.endDate});

  final DateTime? endDate;

  @override
  List<Object?> get props => <Object?>[endDate];
}
