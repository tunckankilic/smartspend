import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';

/// Mints a signed URL for a receipt image (Sprint 8.3).
///
/// Used by `ReceiptDetailBloc` to fall back to Supabase Storage when the
/// locally cached file is no longer on disk.
class GetReceiptImageUrlUseCase
    implements UseCase<String, GetReceiptImageUrlParams> {
  const GetReceiptImageUrlUseCase(this._repository);

  final ReceiptArchiveRepository _repository;

  @override
  Future<Either<Failure, String>> call(GetReceiptImageUrlParams params) {
    return _repository.getReceiptImageUrl(params.objectPath);
  }
}

class GetReceiptImageUrlParams extends Equatable {
  const GetReceiptImageUrlParams({required this.objectPath});

  final String objectPath;

  @override
  List<Object?> get props => <Object?>[objectPath];
}
