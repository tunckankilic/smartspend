import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';
import 'package:smartspend/features/scan/domain/usecases/capture_image.dart';
import 'package:smartspend/features/scan/domain/usecases/pick_image.dart';
import 'package:smartspend/features/scan/domain/usecases/scan_receipt.dart';
import 'package:smartspend/features/scan/domain/usecases/usecase.dart';

class _MockScanRepository extends Mock implements ScanRepository {}

class _FakeFile extends Fake implements File {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeFile());
  });

  late _MockScanRepository repo;
  late File file;

  setUp(() {
    repo = _MockScanRepository();
    file = File('/tmp/x.jpg');
  });

  group('CaptureImageUseCase', () {
    test('should delegate to ScanRepository.captureImage', () async {
      when(() => repo.captureImage())
          .thenAnswer((_) async => Right<Failure, File>(file));

      final CaptureImageUseCase usecase = CaptureImageUseCase(repo);
      final Either<Failure, File> result = await usecase(const NoParams());

      expect(result, Right<Failure, File>(file));
      verify(() => repo.captureImage()).called(1);
    });
  });

  group('PickImageUseCase', () {
    test('should delegate to ScanRepository.pickFromGallery', () async {
      when(() => repo.pickFromGallery())
          .thenAnswer((_) async => Right<Failure, File>(file));

      final PickImageUseCase usecase = PickImageUseCase(repo);
      final Either<Failure, File> result = await usecase(const NoParams());

      expect(result, Right<Failure, File>(file));
      verify(() => repo.pickFromGallery()).called(1);
    });
  });

  group('ScanReceiptUseCase', () {
    test('should forward the image and return the receipt', () async {
      final ScannedReceipt receipt = ScannedReceipt.pending(file.path);
      when(() => repo.scanReceipt(any())).thenAnswer(
        (_) async => Right<Failure, ScannedReceipt>(receipt),
      );

      final ScanReceiptUseCase usecase = ScanReceiptUseCase(repo);
      final Either<Failure, ScannedReceipt> result = await usecase(
        ScanReceiptParams(image: file),
      );

      expect(result, Right<Failure, ScannedReceipt>(receipt));
      verify(() => repo.scanReceipt(file)).called(1);
    });
  });
}
