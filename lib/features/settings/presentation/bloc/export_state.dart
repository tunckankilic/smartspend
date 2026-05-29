part of 'export_cubit.dart';

enum ExportStatus { idle, inProgress, success, failure }

class ExportState extends Equatable {
  const ExportState({
    this.status = ExportStatus.idle,
    this.result,
    this.failure,
  });

  final ExportStatus status;
  final ExportResult? result;
  final Failure? failure;

  ExportState copyWith({
    ExportStatus? status,
    ExportResult? result,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return ExportState(
      status: status ?? this.status,
      result: result ?? this.result,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, result, failure];
}
