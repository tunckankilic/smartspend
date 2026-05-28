part of 'receipt_detail_bloc.dart';

sealed class ReceiptDetailState extends Equatable {
  const ReceiptDetailState();

  @override
  List<Object?> get props => const <Object?>[];
}

final class ReceiptDetailInitial extends ReceiptDetailState {
  const ReceiptDetailInitial();
}

final class ReceiptDetailLoading extends ReceiptDetailState {
  const ReceiptDetailLoading();
}

final class ReceiptDetailReady extends ReceiptDetailState {
  const ReceiptDetailReady({
    required this.detail,
    this.transientFailure,
  });

  final ReceiptDetail detail;
  final Failure? transientFailure;

  ReceiptDetailReady copyWith({
    ReceiptDetail? detail,
    Failure? transientFailure,
    bool clearTransient = false,
  }) {
    return ReceiptDetailReady(
      detail: detail ?? this.detail,
      transientFailure:
          clearTransient ? null : (transientFailure ?? this.transientFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[detail, transientFailure];
}

final class ReceiptDetailError extends ReceiptDetailState {
  const ReceiptDetailError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
