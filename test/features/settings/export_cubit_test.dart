import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';
import 'package:smartspend/features/settings/domain/usecases/export_data.dart';
import 'package:smartspend/features/settings/presentation/bloc/export_cubit.dart';

class _MockExportData extends Mock implements ExportDataUseCase {}

void main() {
  late _MockExportData exportData;

  final ExportResult result = ExportResult(
    url: 'https://example.com/export.csv',
    expiresAt: DateTime.utc(2026, 5, 30),
    rowCount: 42,
  );

  setUpAll(() {
    registerFallbackValue(const ExportParams());
  });

  setUp(() {
    exportData = _MockExportData();
  });

  ExportCubit build() => ExportCubit(exportData: exportData);

  blocTest<ExportCubit, ExportState>(
    'should emit [inProgress, success] with the result on success',
    build: () {
      when(() => exportData(any()))
          .thenAnswer((_) async => Right<Failure, ExportResult>(result));
      return build();
    },
    act: (ExportCubit c) => c.exportData(),
    expect: () => <ExportState>[
      const ExportState(status: ExportStatus.inProgress),
      ExportState(status: ExportStatus.success, result: result),
    ],
  );

  blocTest<ExportCubit, ExportState>(
    'should emit [inProgress, failure] when the export fails',
    build: () {
      when(() => exportData(any())).thenAnswer(
        (_) async =>
            const Left<Failure, ExportResult>(ServerFailure(message: 'x')),
      );
      return build();
    },
    act: (ExportCubit c) => c.exportData(),
    expect: () => <ExportState>[
      const ExportState(status: ExportStatus.inProgress),
      const ExportState(
        status: ExportStatus.failure,
        failure: ServerFailure(message: 'x'),
      ),
    ],
  );

  blocTest<ExportCubit, ExportState>(
    'should carry the PDF format into state and the use-case params',
    build: () {
      when(() => exportData(any()))
          .thenAnswer((_) async => Right<Failure, ExportResult>(result));
      return build();
    },
    act: (ExportCubit c) => c.exportData(format: ExportFormat.pdf),
    expect: () => <ExportState>[
      const ExportState(
        status: ExportStatus.inProgress,
        format: ExportFormat.pdf,
      ),
      ExportState(
        status: ExportStatus.success,
        format: ExportFormat.pdf,
        result: result,
      ),
    ],
    verify: (_) {
      final ExportParams captured =
          verify(() => exportData(captureAny())).captured.single
              as ExportParams;
      expect(captured.format, ExportFormat.pdf);
    },
  );

  blocTest<ExportCubit, ExportState>(
    'should ignore a second export request while one is in flight',
    build: () {
      when(() => exportData(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return Right<Failure, ExportResult>(result);
      });
      return build();
    },
    act: (ExportCubit c) async {
      final Future<void> first = c.exportData();
      await c.exportData();
      await first;
    },
    expect: () => <ExportState>[
      const ExportState(status: ExportStatus.inProgress),
      ExportState(status: ExportStatus.success, result: result),
    ],
    verify: (_) => verify(() => exportData(any())).called(1),
  );
}
