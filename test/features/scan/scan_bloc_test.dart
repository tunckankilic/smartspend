import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/data/datasources/camera_data_source.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/usecases/capture_image.dart';
import 'package:smartspend/features/scan/domain/usecases/pick_image.dart';
import 'package:smartspend/features/scan/domain/usecases/scan_receipt.dart';
import 'package:smartspend/features/scan/domain/usecases/usecase.dart';
import 'package:smartspend/features/scan/presentation/bloc/scan_bloc.dart';

class _MockCapture extends Mock implements CaptureImageUseCase {}

class _MockPick extends Mock implements PickImageUseCase {}

class _MockScanReceipt extends Mock implements ScanReceiptUseCase {}

class _FakeNoParams extends Fake implements NoParams {}

class _FakeScanParams extends Fake implements ScanReceiptParams {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeNoParams());
    registerFallbackValue(_FakeScanParams());
  });

  late _MockCapture capture;
  late _MockPick pick;
  late _MockScanReceipt scanReceipt;
  final File image = File('/tmp/captured.jpg');

  ScanBloc build() => ScanBloc(
    captureImage: capture,
    pickImage: pick,
    scanReceipt: scanReceipt,
  );

  setUp(() {
    capture = _MockCapture();
    pick = _MockPick();
    scanReceipt = _MockScanReceipt();
  });

  test('initial state is ScanInitial', () {
    final ScanBloc bloc = build();
    expect(bloc.state, isA<ScanInitial>());
    bloc.close();
  });

  group('CameraOpened', () {
    blocTest<ScanBloc, ScanState>(
      'should emit [ScanProcessing, ImageReady] on capture success',
      build: () {
        when(() => capture(any()))
            .thenAnswer((_) async => Right<Failure, File>(image));
        return build();
      },
      act: (ScanBloc b) => b.add(const CameraOpened()),
      expect: () => <Matcher>[
        isA<ScanProcessing>(),
        isA<ImageReady>(),
      ],
      verify: (ScanBloc b) {
        expect((b.state as ImageReady).image.path, image.path);
      },
    );

    blocTest<ScanBloc, ScanState>(
      'should silently reset to ScanInitial when user cancels picker',
      build: () {
        when(() => capture(any())).thenAnswer(
          (_) async => const Left<Failure, File>(
            PermissionFailure(
              message: 'cancelled',
              code: kCameraCancelledCode,
            ),
          ),
        );
        return build();
      },
      act: (ScanBloc b) => b.add(const CameraOpened()),
      expect: () => <Matcher>[
        isA<ScanProcessing>(),
        isA<ScanInitial>(),
      ],
    );

    blocTest<ScanBloc, ScanState>(
      'should emit ScanError when capture surfaces a real failure',
      build: () {
        when(() => capture(any())).thenAnswer(
          (_) async => const Left<Failure, File>(
            CacheFailure(message: 'disk full'),
          ),
        );
        return build();
      },
      act: (ScanBloc b) => b.add(const CameraOpened()),
      expect: () => <Matcher>[
        isA<ScanProcessing>(),
        isA<ScanError>(),
      ],
      verify: (ScanBloc b) {
        expect((b.state as ScanError).failure, isA<CacheFailure>());
      },
    );
  });

  group('GalleryOpened', () {
    blocTest<ScanBloc, ScanState>(
      'should emit [ScanProcessing, ImageReady] on gallery pick success',
      build: () {
        when(() => pick(any()))
            .thenAnswer((_) async => Right<Failure, File>(image));
        return build();
      },
      act: (ScanBloc b) => b.add(const GalleryOpened()),
      expect: () => <Matcher>[
        isA<ScanProcessing>(),
        isA<ImageReady>(),
      ],
    );
  });

  group('ScanStarted', () {
    blocTest<ScanBloc, ScanState>(
      'should emit [ScanProcessing, ScanSuccess] when image is ready',
      build: () {
        when(() => scanReceipt(any())).thenAnswer(
          (_) async => Right<Failure, ScannedReceipt>(
            ScannedReceipt.pending(image.path),
          ),
        );
        return build();
      },
      seed: () => ImageReady(image: image),
      act: (ScanBloc b) => b.add(const ScanStarted()),
      expect: () => <Matcher>[
        isA<ScanProcessing>(),
        isA<ScanSuccess>(),
      ],
      verify: (ScanBloc b) {
        expect((b.state as ScanSuccess).receipt.imagePath, image.path);
      },
    );

    blocTest<ScanBloc, ScanState>(
      'should be a no-op when no image is ready',
      build: build,
      act: (ScanBloc b) => b.add(const ScanStarted()),
      expect: () => const <Matcher>[],
    );

    blocTest<ScanBloc, ScanState>(
      'should emit ScanError when scanReceipt fails',
      build: () {
        when(() => scanReceipt(any())).thenAnswer(
          (_) async => const Left<Failure, ScannedReceipt>(
            OCRFailure(message: 'engine down'),
          ),
        );
        return build();
      },
      seed: () => ImageReady(image: image),
      act: (ScanBloc b) => b.add(const ScanStarted()),
      expect: () => <Matcher>[
        isA<ScanProcessing>(),
        isA<ScanError>(),
      ],
    );
  });

  group('manual injection + edit flow', () {
    blocTest<ScanBloc, ScanState>(
      'ImageCaptured(file) should jump straight to ImageReady',
      build: build,
      act: (ScanBloc b) => b.add(ImageCaptured(image: image)),
      expect: () => <Matcher>[isA<ImageReady>()],
    );

    blocTest<ScanBloc, ScanState>(
      'ResultEdited should emit ScanEditing carrying the edited receipt',
      build: build,
      act: (ScanBloc b) => b.add(
        ResultEdited(receipt: ScannedReceipt.pending(image.path)),
      ),
      expect: () => <Matcher>[isA<ScanEditing>()],
    );

    blocTest<ScanBloc, ScanState>(
      'ReceiptConfirmed should transition to ScanSaved',
      build: build,
      act: (ScanBloc b) => b.add(
        ReceiptConfirmed(receipt: ScannedReceipt.pending(image.path)),
      ),
      expect: () => <Matcher>[isA<ScanSaved>()],
    );

    blocTest<ScanBloc, ScanState>(
      'ScanReset should return to ScanInitial from any state',
      build: build,
      seed: () => ImageReady(image: image),
      act: (ScanBloc b) => b.add(const ScanReset()),
      expect: () => <Matcher>[isA<ScanInitial>()],
    );
  });
}
