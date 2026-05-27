// Named params drop their leading underscore by Dart convention; private
// fields keep theirs. The two diverge only in the underscore, so the
// `prefer_initializing_formals` lint fires — suppress here once.
// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/data/datasources/camera_data_source.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/usecases/capture_image.dart';
import 'package:smartspend/features/scan/domain/usecases/pick_image.dart';
import 'package:smartspend/features/scan/domain/usecases/scan_receipt.dart';
import 'package:smartspend/features/scan/domain/usecases/usecase.dart';

part 'scan_event.dart';
part 'scan_state.dart';

/// Owns the scan flow's state machine:
///
/// ```text
/// ScanInitial
///   → ImageCaptured (file in hand, awaiting user confirmation)
///   → ScanProcessing (OCR running)
///   → ScanSuccess  (parsed but not yet user-edited)
///   → ScanEditing  (Sprint 2.3 edit UI — user mutates the receipt)
///   → ScanSaved    (Sprint 2.3 persists to Drift)
/// ```
///
/// Sprint 2.1 only wires capture + the pending stub returned by
/// [ScanReceiptUseCase] — the engine itself lands in Sprint 2.2.
class ScanBloc extends Bloc<ScanEvent, ScanState> {
  ScanBloc({
    required CaptureImageUseCase captureImage,
    required PickImageUseCase pickImage,
    required ScanReceiptUseCase scanReceipt,
  }) : _captureImage = captureImage,
       _pickImage = pickImage,
       _scanReceipt = scanReceipt,
       super(const ScanInitial()) {
    on<CameraOpened>(_onCameraOpened);
    on<GalleryOpened>(_onGalleryOpened);
    on<ImageCaptured>(_onImageCaptured);
    on<ScanStarted>(_onScanStarted);
    on<ResultEdited>(_onResultEdited);
    on<ReceiptConfirmed>(_onReceiptConfirmed);
    on<ScanReset>(_onScanReset);
  }

  final CaptureImageUseCase _captureImage;
  final PickImageUseCase _pickImage;
  final ScanReceiptUseCase _scanReceipt;

  Future<void> _onCameraOpened(
    CameraOpened event,
    Emitter<ScanState> emit,
  ) async {
    emit(const ScanProcessing());
    final Either<Failure, File> result = await _captureImage(const NoParams());
    _handlePickResult(result, emit);
  }

  Future<void> _onGalleryOpened(
    GalleryOpened event,
    Emitter<ScanState> emit,
  ) async {
    emit(const ScanProcessing());
    final Either<Failure, File> result = await _pickImage(const NoParams());
    _handlePickResult(result, emit);
  }

  void _handlePickResult(
    Either<Failure, File> result,
    Emitter<ScanState> emit,
  ) {
    result.fold(
      (Failure f) {
        // User backed out of the system picker → silent reset, no banner.
        if (f.code == kCameraCancelledCode) {
          emit(const ScanInitial());
          return;
        }
        emit(ScanError(failure: f));
      },
      (File file) => emit(ImageReady(image: file)),
    );
  }

  void _onImageCaptured(
    ImageCaptured event,
    Emitter<ScanState> emit,
  ) {
    emit(ImageReady(image: event.image));
  }

  Future<void> _onScanStarted(
    ScanStarted event,
    Emitter<ScanState> emit,
  ) async {
    final ScanState current = state;
    if (current is! ImageReady) {
      // Defensive — UI should not allow ScanStarted without an image.
      return;
    }
    emit(const ScanProcessing());
    final Either<Failure, ScannedReceipt> result = await _scanReceipt(
      ScanReceiptParams(image: current.image),
    );
    result.fold(
      (Failure f) => emit(ScanError(failure: f)),
      (ScannedReceipt receipt) => emit(ScanSuccess(receipt: receipt)),
    );
  }

  void _onResultEdited(
    ResultEdited event,
    Emitter<ScanState> emit,
  ) {
    emit(ScanEditing(receipt: event.receipt));
  }

  void _onReceiptConfirmed(
    ReceiptConfirmed event,
    Emitter<ScanState> emit,
  ) {
    // Sprint 2.3 persists to Drift here. For now we just transition so the
    // state machine is exercised end-to-end.
    emit(ScanSaved(receipt: event.receipt));
  }

  void _onScanReset(ScanReset event, Emitter<ScanState> emit) {
    emit(const ScanInitial());
  }
}
