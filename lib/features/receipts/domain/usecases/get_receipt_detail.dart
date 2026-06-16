import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';

/// One-shot detail read for `ReceiptDetailPage` (Sprint 7).
class GetReceiptDetailUseCase
    implements UseCase<ReceiptDetail, GetReceiptDetailParams> {
  const GetReceiptDetailUseCase(this._repository);

  final ReceiptArchiveRepository _repository;

  @override
  Future<Either<Failure, ReceiptDetail>> call(GetReceiptDetailParams params) {
    return _repository.getDetail(params.receiptId);
  }
}

class GetReceiptDetailParams extends Equatable {
  const GetReceiptDetailParams({required this.receiptId});

  final int receiptId;

  @override
  List<Object?> get props => <Object?>[receiptId];
}
