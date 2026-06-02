part of 'export_cubit.dart';

enum ExportStatus { idle, inProgress, success, failure }

class ExportState extends Equatable {
  const ExportState({
    this.status = ExportStatus.idle,
    this.format = ExportFormat.csv,
    this.result,
    this.failure,
  });

  final ExportStatus status;

  /// The format of the in-progress / most recent export. Lets the UI show a
  /// spinner on the specific button (CSV vs PDF) that was tapped.
  final ExportFormat format;
  final ExportResult? result;
  final Failure? failure;

  ExportState copyWith({
    ExportStatus? status,
    ExportFormat? format,
    ExportResult? result,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return ExportState(
      status: status ?? this.status,
      format: format ?? this.format,
      result: result ?? this.result,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, format, result, failure];
}
