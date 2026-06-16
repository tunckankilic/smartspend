import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/features/scan/data/datasources/gemini_ocr_data_source.dart';
import 'package:smartspend/features/scan/data/datasources/ocr_data_source.dart';

class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  late _MockFunctions functions;
  late GeminiOCRDataSource datasource;
  late File image;

  setUp(() async {
    functions = _MockFunctions();
    datasource = GeminiOCRDataSource(functions: functions);

    // Write a tiny throwaway file so readAsBytes works without ML Kit
    // touching the disk.
    final Directory tmp = Directory.systemTemp.createTempSync('gemini_test_');
    image = File('${tmp.path}/scan.jpg');
    await image.writeAsBytes(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]));
  });

  FunctionResponse okResponse(Map<String, Object?> data) {
    return FunctionResponse(data: data, status: 200);
  }

  test('should parse a well-formed envelope', () async {
    when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => okResponse(<String, Object?>{
        'data': <String, Object?>{
          'raw_text': 'TOPLAM 25,40',
          'confidence': 0.93,
        },
        'error': null,
      }),
    );

    final OCRResult got = await datasource.recognizeText(image);

    expect(got.engine, OCREngine.gemini);
    expect(got.rawText, 'TOPLAM 25,40');
    expect(got.confidence, 0.93);
  });

  test('should default confidence to 0.9 when absent', () async {
    when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => okResponse(<String, Object?>{
        'data': <String, Object?>{'raw_text': 'OK'},
        'error': null,
      }),
    );

    final OCRResult got = await datasource.recognizeText(image);

    expect(got.confidence, 0.9);
  });

  test('should throw RateLimitException on HTTP 429', () async {
    when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => FunctionResponse(
        data: <String, Object?>{
          'data': null,
          'error': <String, Object?>{'code': 'RATE_LIMIT'},
        },
        status: 429,
      ),
    );

    await expectLater(
      datasource.recognizeText(image),
      throwsA(isA<RateLimitException>()),
    );
  });

  test('should throw OCRException on HTTP 401 (auth)', () async {
    when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => FunctionResponse(data: null, status: 401),
    );

    await expectLater(
      datasource.recognizeText(image),
      throwsA(
        isA<OCRException>().having(
          (OCRException e) => e.code,
          'code',
          'gemini_unauthorized',
        ),
      ),
    );
  });

  test('should throw OCRException on malformed payload', () async {
    when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => okResponse(<String, Object?>{'not_data': 'oops'}),
    );

    await expectLater(
      datasource.recognizeText(image),
      throwsA(isA<OCRException>()),
    );
  });
}
