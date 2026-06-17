import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/features/settings/data/datasources/export_remote_data_source.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';

class _MockFunctionsClient extends Mock implements FunctionsClient {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const String _kUrl = 'https://storage.example.com/export.csv';
const String _kExpiresAt = '2026-06-18T10:00:00.000Z';
const int _kRowCount = 42;

FunctionResponse _goodResponse({
  String url = _kUrl,
  String expiresAt = _kExpiresAt,
  int rowCount = _kRowCount,
}) {
  return FunctionResponse(
    status: 200,
    data: <String, Object?>{
      'data': <String, Object?>{
        'url': url,
        'expires_at': expiresAt,
        'row_count': rowCount,
      },
    },
  );
}

void main() {
  late _MockFunctionsClient functions;
  late SupabaseExportRemoteDataSource dataSource;

  setUpAll(() {
    registerFallbackValue(HttpMethod.get);
  });

  setUp(() {
    functions = _MockFunctionsClient();
    dataSource = SupabaseExportRemoteDataSource(functions: functions);
  });

  // ---------------------------------------------------------------------------
  // Success paths
  // ---------------------------------------------------------------------------

  group('exportExpenses — success', () {
    test('should return ExportResult on a well-formed CSV response', () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => _goodResponse());

      final ExportResult result = await dataSource.exportExpenses(
        format: ExportFormat.csv,
      );

      expect(result.url, _kUrl);
      expect(result.expiresAt, DateTime.parse(_kExpiresAt));
      expect(result.rowCount, _kRowCount);
    });

    test('should invoke the pdf function name when format is ExportFormat.pdf',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => _goodResponse());

      await dataSource.exportExpenses(format: ExportFormat.pdf);

      verify(() => functions.invoke(
                'export-pdf',
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .called(1);
    });

    test('should invoke the csv function name when format is ExportFormat.csv',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => _goodResponse());

      await dataSource.exportExpenses(format: ExportFormat.csv);

      verify(() => functions.invoke(
                'export-csv',
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .called(1);
    });

    test('should pass null queryParameters when no dates are given', () async {
      Map<String, dynamic>? captured;

      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((Invocation inv) async {
        captured = inv.namedArguments[#queryParameters]
            as Map<String, dynamic>?;
        return _goodResponse();
      });

      await dataSource.exportExpenses(format: ExportFormat.csv);

      expect(captured, isNull);
    });

    test('should pass from_date and to_date as yyyy-MM-dd query params',
        () async {
      Map<String, dynamic>? captured;

      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((Invocation inv) async {
        captured = inv.namedArguments[#queryParameters]
            as Map<String, dynamic>?;
        return _goodResponse();
      });

      await dataSource.exportExpenses(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 3, 31),
        format: ExportFormat.csv,
      );

      expect(captured, isNotNull);
      expect(captured!['from_date'], '2026-01-01');
      expect(captured!['to_date'], '2026-03-31');
    });

    test('should use HttpMethod.get when invoking the function', () async {
      HttpMethod? capturedMethod;

      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((Invocation inv) async {
        capturedMethod =
            inv.namedArguments[#method] as HttpMethod?;
        return _goodResponse();
      });

      await dataSource.exportExpenses(format: ExportFormat.csv);

      expect(capturedMethod, HttpMethod.get);
    });
  });

  // ---------------------------------------------------------------------------
  // HTTP error path
  // ---------------------------------------------------------------------------

  group('exportExpenses — HTTP errors', () {
    test('should throw ServerException when status is 400', () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => FunctionResponse(status: 400, data: null));

      expect(
        () => dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });

    test('should throw ServerException when status is 500', () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => FunctionResponse(status: 500, data: null));

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Bad payload shapes
  // ---------------------------------------------------------------------------

  group('exportExpenses — bad payload shapes', () {
    test('should throw ServerException when data is not a Map', () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer(
            (_) async => FunctionResponse(status: 200, data: 'plain string'),
          );

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });

    test('should throw ServerException when "data" envelope key is missing',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: <String, Object?>{'other': 'value'},
              ));

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });

    test('should throw ServerException when "data" envelope is not a Map',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: <String, Object?>{'data': 'not-a-map'},
              ));

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });

    test(
        'should throw ServerException when "url" field is missing from payload',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: <String, Object?>{
                  'data': <String, Object?>{
                    'expires_at': _kExpiresAt,
                    'row_count': _kRowCount,
                    // 'url' intentionally missing
                  },
                },
              ));

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });

    test('should throw ServerException when "row_count" is a String, not int',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: <String, Object?>{
                  'data': <String, Object?>{
                    'url': _kUrl,
                    'expires_at': _kExpiresAt,
                    'row_count': '42', // String instead of int
                  },
                },
              ));

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // FunctionException and generic Exception
  // ---------------------------------------------------------------------------

  group('exportExpenses — SDK exceptions', () {
    test('should throw ServerException when FunctionException is thrown',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenThrow(
            const FunctionException(status: 503, details: 'service unavail'),
          );

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });

    test('should throw ServerException when a generic Exception is thrown',
        () async {
      when(() => functions.invoke(
                any(),
                method: any(named: 'method'),
                queryParameters: any(named: 'queryParameters'),
              ))
          .thenThrow(Exception('network timeout'));

      await expectLater(
        dataSource.exportExpenses(format: ExportFormat.csv),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
