import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/usecases/add_warranty.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_image_url.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_detail_bloc.dart';

class _MockGetDetail extends Mock implements GetReceiptDetailUseCase {}

class _MockAddWarranty extends Mock implements AddWarrantyUseCase {}

class _MockGetImageUrl extends Mock implements GetReceiptImageUrlUseCase {}

ReceiptDetail _detail({String? storageObjectPath}) => ReceiptDetail(
  id: 1,
  date: DateTime.utc(2026, 5, 1),
  totalMinor: 1299,
  currency: 'TRY',
  items: const <ReceiptDetailItem>[],
  storageObjectPath: storageObjectPath,
);

void main() {
  late _MockGetDetail getDetail;
  late _MockAddWarranty addWarranty;
  late _MockGetImageUrl getImageUrl;

  setUpAll(() {
    registerFallbackValue(const GetReceiptDetailParams(receiptId: 1));
    registerFallbackValue(const GetReceiptImageUrlParams(objectPath: 'x'));
    registerFallbackValue(const AddWarrantyParams(receiptId: 1, endDate: null));
  });

  setUp(() {
    getDetail = _MockGetDetail();
    addWarranty = _MockAddWarranty();
    getImageUrl = _MockGetImageUrl();
  });

  ReceiptDetailBloc build() => ReceiptDetailBloc(
    getDetail: getDetail,
    addWarranty: addWarranty,
    getImageUrl: getImageUrl,
  );

  group('ReceiptDetailLoaded', () {
    blocTest<ReceiptDetailBloc, ReceiptDetailState>(
      'should resolve the signed URL when the image is available',
      setUp: () {
        when(() => getDetail(any())).thenAnswer(
          (_) async => Right<Failure, ReceiptDetail>(
            _detail(storageObjectPath: 'u/1/full.jpg'),
          ),
        );
        when(() => getImageUrl(any())).thenAnswer(
          (_) async => const Right<Failure, String>('https://signed.example'),
        );
      },
      build: build,
      act: (ReceiptDetailBloc b) =>
          b.add(const ReceiptDetailLoaded(receiptId: 1)),
      verify: (_) {
        verify(() => getImageUrl(any())).called(1);
      },
      expect: () => <Matcher>[
        isA<ReceiptDetailLoading>(),
        isA<ReceiptDetailReady>()
            .having((ReceiptDetailReady s) => s.signedImageUrl, 'url', null)
            .having(
              (ReceiptDetailReady s) => s.imageUnavailable,
              'flag',
              false,
            ),
        isA<ReceiptDetailReady>()
            .having(
              (ReceiptDetailReady s) => s.signedImageUrl,
              'url',
              'https://signed.example',
            )
            .having(
              (ReceiptDetailReady s) => s.imageUnavailable,
              'flag',
              false,
            ),
      ],
    );

    blocTest<ReceiptDetailBloc, ReceiptDetailState>(
      'should flag imageUnavailable when the signed URL cannot be resolved',
      setUp: () {
        when(() => getDetail(any())).thenAnswer(
          (_) async => Right<Failure, ReceiptDetail>(
            _detail(storageObjectPath: 'u/1/full.jpg'),
          ),
        );
        when(() => getImageUrl(any())).thenAnswer(
          (_) async => const Left<Failure, String>(
            ServerFailure(message: 'no object'),
          ),
        );
      },
      build: build,
      act: (ReceiptDetailBloc b) =>
          b.add(const ReceiptDetailLoaded(receiptId: 1)),
      expect: () => <Matcher>[
        isA<ReceiptDetailLoading>(),
        isA<ReceiptDetailReady>().having(
          (ReceiptDetailReady s) => s.imageUnavailable,
          'flag',
          false,
        ),
        isA<ReceiptDetailReady>().having(
          (ReceiptDetailReady s) => s.imageUnavailable,
          'flag',
          true,
        ),
      ],
    );

    blocTest<ReceiptDetailBloc, ReceiptDetailState>(
      'should not touch storage when there is no remote object path',
      setUp: () {
        when(() => getDetail(any())).thenAnswer(
          (_) async => Right<Failure, ReceiptDetail>(_detail()),
        );
      },
      build: build,
      act: (ReceiptDetailBloc b) =>
          b.add(const ReceiptDetailLoaded(receiptId: 1)),
      verify: (_) {
        verifyNever(() => getImageUrl(any()));
      },
      expect: () => <Matcher>[
        isA<ReceiptDetailLoading>(),
        isA<ReceiptDetailReady>().having(
          (ReceiptDetailReady s) => s.imageUnavailable,
          'flag',
          false,
        ),
      ],
    );

    blocTest<ReceiptDetailBloc, ReceiptDetailState>(
      'should emit ReceiptDetailError when the detail read fails',
      setUp: () {
        when(() => getDetail(any())).thenAnswer(
          (_) async => const Left<Failure, ReceiptDetail>(
            CacheFailure(message: 'row gone'),
          ),
        );
      },
      build: build,
      act: (ReceiptDetailBloc b) =>
          b.add(const ReceiptDetailLoaded(receiptId: 1)),
      verify: (_) {
        verifyNever(() => getImageUrl(any()));
      },
      expect: () => <Matcher>[
        isA<ReceiptDetailLoading>(),
        isA<ReceiptDetailError>(),
      ],
    );
  });

  group('ReceiptWarrantyChanged', () {
    final DateTime endDate = DateTime.utc(2027, 5, 1);

    blocTest<ReceiptDetailBloc, ReceiptDetailState>(
      'should ignore warranty edits before the detail is loaded',
      build: build,
      act: (ReceiptDetailBloc b) =>
          b.add(ReceiptWarrantyChanged(endDate: endDate)),
      verify: (_) {
        verifyNever(() => addWarranty(any()));
      },
      expect: () => <Matcher>[],
    );

    blocTest<ReceiptDetailBloc, ReceiptDetailState>(
      'should patch the warranty end date into the ready state',
      setUp: () {
        when(() => getDetail(any())).thenAnswer(
          (_) async => Right<Failure, ReceiptDetail>(_detail()),
        );
        when(() => addWarranty(any())).thenAnswer(
          (_) async => const Right<Failure, void>(null),
        );
      },
      build: build,
      act: (ReceiptDetailBloc b) async {
        b.add(const ReceiptDetailLoaded(receiptId: 1));
        await Future<void>.delayed(Duration.zero);
        b.add(ReceiptWarrantyChanged(endDate: endDate));
      },
      skip: 2, // Loading + initial Ready
      expect: () => <Matcher>[
        isA<ReceiptDetailReady>().having(
          (ReceiptDetailReady s) => s.detail.warrantyEndDate,
          'warrantyEndDate',
          endDate,
        ),
      ],
    );

    blocTest<ReceiptDetailBloc, ReceiptDetailState>(
      'should surface a transient failure when the warranty write fails',
      setUp: () {
        when(() => getDetail(any())).thenAnswer(
          (_) async => Right<Failure, ReceiptDetail>(_detail()),
        );
        when(() => addWarranty(any())).thenAnswer(
          (_) async => const Left<Failure, void>(
            CacheFailure(message: 'write failed'),
          ),
        );
      },
      build: build,
      act: (ReceiptDetailBloc b) async {
        b.add(const ReceiptDetailLoaded(receiptId: 1));
        await Future<void>.delayed(Duration.zero);
        b.add(ReceiptWarrantyChanged(endDate: endDate));
      },
      skip: 2, // Loading + initial Ready
      expect: () => <Matcher>[
        isA<ReceiptDetailReady>()
            .having(
              (ReceiptDetailReady s) => s.transientFailure,
              'transientFailure',
              isA<CacheFailure>(),
            )
            .having(
              (ReceiptDetailReady s) => s.detail.warrantyEndDate,
              'warrantyEndDate',
              isNull,
            ),
      ],
    );
  });
}
