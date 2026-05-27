import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/features/scan/data/datasources/hybrid_ocr_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';

class _MockOCR extends Mock implements OCRDataSource {}

class _MockConnectivity extends Mock implements Connectivity {}

class _FakeFile extends Fake implements File {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeFile());
  });

  late _MockOCR mlKit;
  late _MockOCR gemini;
  late _MockConnectivity connectivity;
  late HybridOCRDataSource hybrid;
  final File image = File('/tmp/scan.jpg');

  OCRResult result({
    required double confidence,
    OCREngine engine = OCREngine.mlKit,
    String text = 'TOPLAM 25,40',
  }) {
    return OCRResult(
      rawText: text,
      blocks: <OCRTextBlock>[
        OCRTextBlock(text: text, confidence: confidence),
      ],
      confidence: confidence,
      engine: engine,
    );
  }

  setUp(() {
    mlKit = _MockOCR();
    gemini = _MockOCR();
    connectivity = _MockConnectivity();
    hybrid = HybridOCRDataSource(
      mlKit: mlKit,
      gemini: gemini,
      connectivity: connectivity,
    );
  });

  void mockOnline({bool online = true}) {
    when(() => connectivity.checkConnectivity()).thenAnswer(
      (_) async => online
          ? <ConnectivityResult>[ConnectivityResult.wifi]
          : <ConnectivityResult>[ConnectivityResult.none],
    );
  }

  test('should return ML Kit result when confidence is above threshold',
      () async {
    when(() => mlKit.recognizeText(any())).thenAnswer(
      (_) async => result(confidence: 0.92),
    );

    final OCRResult got = await hybrid.recognizeText(image);

    expect(got.engine, OCREngine.mlKit);
    expect(got.confidence, 0.92);
    verifyNever(() => gemini.recognizeText(any()));
  });

  test('should escalate to Gemini when ML Kit confidence is below threshold',
      () async {
    when(() => mlKit.recognizeText(any())).thenAnswer(
      (_) async => result(confidence: 0.4),
    );
    mockOnline();
    when(() => gemini.recognizeText(any())).thenAnswer(
      (_) async => result(confidence: 0.93, engine: OCREngine.gemini),
    );

    final OCRResult got = await hybrid.recognizeText(image);

    expect(got.engine, OCREngine.gemini);
    verify(() => gemini.recognizeText(any())).called(1);
  });

  test('should keep ML Kit result when offline even if confidence is low',
      () async {
    when(() => mlKit.recognizeText(any())).thenAnswer(
      (_) async => result(confidence: 0.5),
    );
    mockOnline(online: false);

    final OCRResult got = await hybrid.recognizeText(image);

    expect(got.engine, OCREngine.mlKit);
    verifyNever(() => gemini.recognizeText(any()));
  });

  test('should try Gemini when ML Kit throws and we are online', () async {
    when(() => mlKit.recognizeText(any())).thenThrow(
      const OCRException(message: 'recognizer crashed'),
    );
    mockOnline();
    when(() => gemini.recognizeText(any())).thenAnswer(
      (_) async => result(confidence: 0.91, engine: OCREngine.gemini),
    );

    final OCRResult got = await hybrid.recognizeText(image);

    expect(got.engine, OCREngine.gemini);
  });

  test('should throw OCRException when offline and ML Kit also fails',
      () async {
    when(() => mlKit.recognizeText(any())).thenThrow(
      const OCRException(message: 'recognizer crashed'),
    );
    mockOnline(online: false);

    expect(
      () => hybrid.recognizeText(image),
      throwsA(isA<OCRException>()),
    );
    verifyNever(() => gemini.recognizeText(any()));
  });

  test('should fall back to ML Kit result when Gemini is rate-limited',
      () async {
    when(() => mlKit.recognizeText(any())).thenAnswer(
      (_) async => result(confidence: 0.4),
    );
    mockOnline();
    when(() => gemini.recognizeText(any())).thenThrow(
      const RateLimitException(message: 'limit'),
    );

    final OCRResult got = await hybrid.recognizeText(image);

    expect(got.engine, OCREngine.mlKit);
  });

  test('should propagate RateLimitException when ML Kit also failed',
      () async {
    when(() => mlKit.recognizeText(any())).thenThrow(
      const OCRException(message: 'crashed'),
    );
    mockOnline();
    when(() => gemini.recognizeText(any())).thenThrow(
      const RateLimitException(message: 'limit'),
    );

    expect(
      () => hybrid.recognizeText(image),
      throwsA(isA<RateLimitException>()),
    );
  });

  test('should fall back to ML Kit when Gemini generic error', () async {
    when(() => mlKit.recognizeText(any())).thenAnswer(
      (_) async => result(confidence: 0.4),
    );
    mockOnline();
    when(() => gemini.recognizeText(any())).thenThrow(
      const OCRException(message: 'gemini down'),
    );

    final OCRResult got = await hybrid.recognizeText(image);

    expect(got.engine, OCREngine.mlKit);
  });
}
