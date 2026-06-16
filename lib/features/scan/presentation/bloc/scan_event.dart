part of 'scan_bloc.dart';

/// Inputs to the [ScanBloc] state machine.
sealed class ScanEvent extends Equatable {
  const ScanEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// User tapped the camera shutter button → open the system camera.
final class CameraOpened extends ScanEvent {
  const CameraOpened();
}

/// User tapped the gallery icon → open the photo library picker.
final class GalleryOpened extends ScanEvent {
  const GalleryOpened();
}

/// An image is in hand (e.g. injected by a custom camera preview widget).
/// Bypasses the system picker.
final class ImageCaptured extends ScanEvent {
  const ImageCaptured({required this.image});

  final File image;

  @override
  List<Object?> get props => <Object?>[image.path];
}

/// User confirmed the captured image and wants to run OCR.
final class ScanStarted extends ScanEvent {
  const ScanStarted();
}

/// User mutated a field while reviewing — emitted from the edit UI in
/// Sprint 2.3.
final class ResultEdited extends ScanEvent {
  const ResultEdited({required this.receipt});

  final ScannedReceipt receipt;

  @override
  List<Object?> get props => <Object?>[receipt];
}

/// User pressed Save on the review screen — persistence lands in Sprint 2.3.
final class ReceiptConfirmed extends ScanEvent {
  const ReceiptConfirmed({required this.receipt});

  final ScannedReceipt receipt;

  @override
  List<Object?> get props => <Object?>[receipt];
}

/// Reset the flow (e.g. user tapped "Retake" or backed out of the page).
final class ScanReset extends ScanEvent {
  const ScanReset();
}
