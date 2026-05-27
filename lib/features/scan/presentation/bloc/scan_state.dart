part of 'scan_bloc.dart';

/// Outputs of [ScanBloc].
sealed class ScanState extends Equatable {
  const ScanState();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Idle — waiting for the user to capture or pick an image.
final class ScanInitial extends ScanState {
  const ScanInitial();
}

/// An image is in hand (captured or picked + preprocessed) and awaiting
/// user confirmation. The UI shows a preview with "Scan" and "Retake".
final class ImageReady extends ScanState {
  const ImageReady({required this.image});

  final File image;

  @override
  List<Object?> get props => <Object?>[image.path];
}

/// A long-running operation (picker is open, or OCR is running).
final class ScanProcessing extends ScanState {
  const ScanProcessing();
}

/// OCR produced a structured receipt — review UI not yet shown.
final class ScanSuccess extends ScanState {
  const ScanSuccess({required this.receipt});

  final ScannedReceipt receipt;

  @override
  List<Object?> get props => <Object?>[receipt];
}

/// User is editing fields on the review screen (Sprint 2.3).
final class ScanEditing extends ScanState {
  const ScanEditing({required this.receipt});

  final ScannedReceipt receipt;

  @override
  List<Object?> get props => <Object?>[receipt];
}

/// User confirmed + persistence ran. Bloc resets to [ScanInitial] after the
/// caller has consumed this terminal state.
final class ScanSaved extends ScanState {
  const ScanSaved({required this.receipt});

  final ScannedReceipt receipt;

  @override
  List<Object?> get props => <Object?>[receipt];
}

/// Something went wrong. The UI surfaces [failure.message] and a Retry CTA.
final class ScanError extends ScanState {
  const ScanError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
