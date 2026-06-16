import 'dart:io';

import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';
import 'package:smartspend/features/scan/domain/usecases/usecase.dart';

/// Opens the photo library picker and returns the selected image.
class PickImageUseCase implements UseCase<File, NoParams> {
  const PickImageUseCase(this._repository);

  final ScanRepository _repository;

  @override
  Future<Either<Failure, File>> call(NoParams params) {
    return _repository.pickFromGallery();
  }
}
