import 'dart:io';

import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';
import 'package:smartspend/features/scan/domain/usecases/usecase.dart';

/// Triggers the system camera and returns the captured image file.
class CaptureImageUseCase implements UseCase<File, NoParams> {
  const CaptureImageUseCase(this._repository);

  final ScanRepository _repository;

  @override
  Future<Either<Failure, File>> call(NoParams params) {
    return _repository.captureImage();
  }
}
