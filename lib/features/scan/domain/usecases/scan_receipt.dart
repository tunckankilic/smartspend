import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';
import 'package:smartspend/features/scan/domain/usecases/usecase.dart';

/// Runs the OCR pipeline over a captured image.
class ScanReceiptUseCase implements UseCase<ScannedReceipt, ScanReceiptParams> {
  const ScanReceiptUseCase(this._repository);

  final ScanRepository _repository;

  @override
  Future<Either<Failure, ScannedReceipt>> call(ScanReceiptParams params) {
    return _repository.scanReceipt(params.image);
  }
}

class ScanReceiptParams extends Equatable {
  const ScanReceiptParams({required this.image});

  final File image;

  @override
  List<Object?> get props => <Object?>[image.path];
}
