import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/exceptions.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/data/datasources/export_remote_data_source.dart';
import 'package:smartspend/features/settings/data/repositories/export_repository_impl.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';

class _MockExportRemoteDataSource extends Mock
    implements ExportRemoteDataSource {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final ExportResult _result = ExportResult(
  url: 'https://storage.example.com/export.csv',
  expiresAt: DateTime.utc(2026, 6, 18, 10),
  rowCount: 100,
);

void main() {
  late _MockExportRemoteDataSource remote;
  late ExportRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(ExportFormat.csv);
  });

  setUp(() {
    remote = _MockExportRemoteDataSource();
    repository = ExportRepositoryImpl(remote);
  });

  group('ExportRepositoryImpl.exportExpenses()', () {
    group('success', () {
      test('should return Right(ExportResult) when datasource succeeds',
          () async {
        when(() => remote.exportExpenses(
                  from: any(named: 'from'),
                  to: any(named: 'to'),
                  format: any(named: 'format'),
                ))
            .thenAnswer((_) async => _result);

        final Either<Failure, ExportResult> result =
            await repository.exportExpenses(format: ExportFormat.csv);

        expect(result, Right<Failure, ExportResult>(_result));
      });

      test('should forward format=csv to the datasource', () async {
        when(() => remote.exportExpenses(
                  from: any(named: 'from'),
                  to: any(named: 'to'),
                  format: any(named: 'format'),
                ))
            .thenAnswer((_) async => _result);

        await repository.exportExpenses(format: ExportFormat.csv);

        verify(() => remote.exportExpenses(
              from: any(named: 'from'),
              to: any(named: 'to'),
              format: ExportFormat.csv,
            )).called(1);
      });

      test('should forward format=pdf to the datasource', () async {
        when(() => remote.exportExpenses(
                  from: any(named: 'from'),
                  to: any(named: 'to'),
                  format: any(named: 'format'),
                ))
            .thenAnswer((_) async => _result);

        await repository.exportExpenses(format: ExportFormat.pdf);

        verify(() => remote.exportExpenses(
              from: any(named: 'from'),
              to: any(named: 'to'),
              format: ExportFormat.pdf,
            )).called(1);
      });

      test('should forward from and to dates to the datasource', () async {
        final DateTime from = DateTime.utc(2026, 1, 1);
        final DateTime to = DateTime.utc(2026, 3, 31);

        when(() => remote.exportExpenses(
                  from: any(named: 'from'),
                  to: any(named: 'to'),
                  format: any(named: 'format'),
                ))
            .thenAnswer((_) async => _result);

        await repository.exportExpenses(
          from: from,
          to: to,
          format: ExportFormat.csv,
        );

        verify(() => remote.exportExpenses(
              from: from,
              to: to,
              format: ExportFormat.csv,
            )).called(1);
      });
    });

    group('ServerException → Left(ServerFailure)', () {
      test(
          'should return Left(ServerFailure) when datasource throws'
          ' ServerException',
          () async {
        const ServerException exception =
            ServerException(message: 'export-csv returned HTTP 500.');

        when(() => remote.exportExpenses(
                  from: any(named: 'from'),
                  to: any(named: 'to'),
                  format: any(named: 'format'),
                ))
            .thenThrow(exception);

        final Either<Failure, ExportResult> result =
            await repository.exportExpenses(format: ExportFormat.csv);

        expect(result, isA<Left<Failure, ExportResult>>());
        final ServerFailure failure =
            (result as Left<Failure, ExportResult>).value as ServerFailure;
        expect(failure.message, exception.message);
      });
    });

    group('generic Exception → Left(ServerFailure)', () {
      test(
          'should return Left(ServerFailure) when datasource throws'
          ' a generic Exception',
          () async {
        when(() => remote.exportExpenses(
                  from: any(named: 'from'),
                  to: any(named: 'to'),
                  format: any(named: 'format'),
                ))
            .thenThrow(Exception('network error'));

        final Either<Failure, ExportResult> result =
            await repository.exportExpenses(format: ExportFormat.csv);

        expect(result, isA<Left<Failure, ExportResult>>());
        final Failure failure =
            (result as Left<Failure, ExportResult>).value;
        expect(failure, isA<ServerFailure>());
        expect(failure.message, contains('Export failed'));
      });
    });
  });
}
