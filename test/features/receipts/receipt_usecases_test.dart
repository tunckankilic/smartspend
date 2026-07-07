import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_image_url.dart';

class _MockRepository extends Mock implements ReceiptArchiveRepository {}

void main() {
  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
  });

  group('GetReceiptDetailUseCase', () {
    final ReceiptDetail detail = ReceiptDetail(
      id: 7,
      date: DateTime.utc(2026, 5, 1),
      totalMinor: 1299,
      currency: 'TRY',
      items: const <ReceiptDetailItem>[],
    );

    test('should forward the receipt id to the repository', () async {
      when(() => repository.getDetail(7)).thenAnswer(
        (_) async => Right<Failure, ReceiptDetail>(detail),
      );

      final Either<Failure, ReceiptDetail> result =
          await GetReceiptDetailUseCase(repository)(
            const GetReceiptDetailParams(receiptId: 7),
          );

      expect(result, Right<Failure, ReceiptDetail>(detail));
      verify(() => repository.getDetail(7)).called(1);
    });

    test('should pass a repository failure through unchanged', () async {
      when(() => repository.getDetail(7)).thenAnswer(
        (_) async => const Left<Failure, ReceiptDetail>(
          CacheFailure(message: 'gone'),
        ),
      );

      final Either<Failure, ReceiptDetail> result =
          await GetReceiptDetailUseCase(repository)(
            const GetReceiptDetailParams(receiptId: 7),
          );

      expect(result.isLeft(), isTrue);
    });

    test('should compare params by receipt id', () {
      expect(
        const GetReceiptDetailParams(receiptId: 7),
        const GetReceiptDetailParams(receiptId: 7),
      );
      expect(
        const GetReceiptDetailParams(receiptId: 7),
        isNot(const GetReceiptDetailParams(receiptId: 8)),
      );
    });
  });

  group('GetReceiptImageUrlUseCase', () {
    test('should mint a signed URL for the object path', () async {
      when(() => repository.getReceiptImageUrl('u/7/full.jpg')).thenAnswer(
        (_) async => const Right<Failure, String>('https://signed.example'),
      );

      final Either<Failure, String> result =
          await GetReceiptImageUrlUseCase(repository)(
            const GetReceiptImageUrlParams(objectPath: 'u/7/full.jpg'),
          );

      expect(result, const Right<Failure, String>('https://signed.example'));
      verify(() => repository.getReceiptImageUrl('u/7/full.jpg')).called(1);
    });

    test('should pass a storage failure through unchanged', () async {
      when(() => repository.getReceiptImageUrl('u/7/full.jpg')).thenAnswer(
        (_) async => const Left<Failure, String>(
          ServerFailure(message: 'no object'),
        ),
      );

      final Either<Failure, String> result =
          await GetReceiptImageUrlUseCase(repository)(
            const GetReceiptImageUrlParams(objectPath: 'u/7/full.jpg'),
          );

      expect(result.isLeft(), isTrue);
    });

    test('should compare params by object path', () {
      expect(
        const GetReceiptImageUrlParams(objectPath: 'a'),
        const GetReceiptImageUrlParams(objectPath: 'a'),
      );
      expect(
        const GetReceiptImageUrlParams(objectPath: 'a'),
        isNot(const GetReceiptImageUrlParams(objectPath: 'b')),
      );
    });
  });
}
