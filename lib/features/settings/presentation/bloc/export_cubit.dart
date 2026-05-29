// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';
import 'package:smartspend/features/settings/domain/usecases/export_data.dart';

part 'export_state.dart';

/// Drives the "download my data" action: requests a server-side CSV export
/// and surfaces the signed URL (or a failure) for the UI to act on.
class ExportCubit extends Cubit<ExportState> {
  ExportCubit({required ExportDataUseCase exportData})
    : _exportData = exportData,
      super(const ExportState());

  final ExportDataUseCase _exportData;

  Future<void> exportData({DateTime? from, DateTime? to}) async {
    if (state.status == ExportStatus.inProgress) return;
    emit(state.copyWith(status: ExportStatus.inProgress, clearFailure: true));
    final Either<Failure, ExportResult> result =
        await _exportData(ExportParams(from: from, to: to));
    result.fold(
      (Failure f) => emit(
        state.copyWith(status: ExportStatus.failure, failure: f),
      ),
      (ExportResult r) => emit(
        state.copyWith(status: ExportStatus.success, result: r),
      ),
    );
  }

  /// Returns the cubit to idle after the UI has consumed a result/failure.
  void reset() => emit(const ExportState());
}
