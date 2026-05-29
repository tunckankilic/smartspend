// Private-field naming convention — see BudgetBloc for the same
// pattern. The explicit bindings keep the ctor signature symmetrical.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/usecases/add_warranty.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_detail.dart';
import 'package:smartspend/features/receipts/domain/usecases/get_receipt_image_url.dart';

part 'receipt_detail_event.dart';
part 'receipt_detail_state.dart';

/// Page-scoped state machine for `ReceiptDetailPage` (Sprint 7).
///
/// One-shot read on mount + warranty edits. Re-reads detail after a
/// successful warranty patch so the chip / picker reflects the new
/// state without needing a Drift watch.
class ReceiptDetailBloc extends Bloc<ReceiptDetailEvent, ReceiptDetailState> {
  ReceiptDetailBloc({
    required GetReceiptDetailUseCase getDetail,
    required AddWarrantyUseCase addWarranty,
    required GetReceiptImageUrlUseCase getImageUrl,
  })  : _getDetail = getDetail,
        _addWarranty = addWarranty,
        _getImageUrl = getImageUrl,
        super(const ReceiptDetailInitial()) {
    on<ReceiptDetailLoaded>(_onLoaded, transformer: droppable());
    on<ReceiptWarrantyChanged>(_onWarrantyChanged, transformer: sequential());
  }

  final GetReceiptDetailUseCase _getDetail;
  final AddWarrantyUseCase _addWarranty;
  final GetReceiptImageUrlUseCase _getImageUrl;

  Future<void> _onLoaded(
    ReceiptDetailLoaded event,
    Emitter<ReceiptDetailState> emit,
  ) async {
    emit(const ReceiptDetailLoading());
    final Either<Failure, ReceiptDetail> result =
        await _getDetail(GetReceiptDetailParams(receiptId: event.receiptId));
    final ReceiptDetail? detail = result.fold(
      (Failure f) {
        emit(ReceiptDetailError(failure: f));
        return null;
      },
      (ReceiptDetail d) {
        emit(ReceiptDetailReady(detail: d));
        return d;
      },
    );
    if (detail == null) return;

    // Lazy signed-URL resolution: only needed as a fallback when the local
    // cached file is gone. The widget prefers the local file; if the signed
    // URL cannot be resolved we flag `imageUnavailable` so the UI shows the
    // `storageImageMissing` notice instead of a bare placeholder.
    final String? objectPath = detail.storageObjectPath;
    if (objectPath == null || objectPath.isEmpty) return;
    final Either<Failure, String> url =
        await _getImageUrl(GetReceiptImageUrlParams(objectPath: objectPath));
    final ReceiptDetailState current = state;
    if (current is! ReceiptDetailReady) return;
    url.fold(
      (Failure _) => emit(current.copyWith(imageUnavailable: true)),
      (String signed) => emit(current.copyWith(signedImageUrl: signed)),
    );
  }

  Future<void> _onWarrantyChanged(
    ReceiptWarrantyChanged event,
    Emitter<ReceiptDetailState> emit,
  ) async {
    final ReceiptDetailState s = state;
    if (s is! ReceiptDetailReady) return;
    final Either<Failure, void> result = await _addWarranty(
      AddWarrantyParams(
        receiptId: s.detail.id,
        endDate: event.endDate,
        storeName: s.detail.storeName,
      ),
    );
    result.fold(
      (Failure f) => emit(s.copyWith(transientFailure: f)),
      (_) => emit(
        s.copyWith(
          detail: ReceiptDetail(
            id: s.detail.id,
            storeName: s.detail.storeName,
            date: s.detail.date,
            totalMinor: s.detail.totalMinor,
            currency: s.detail.currency,
            imagePath: s.detail.imagePath,
            storageObjectPath: s.detail.storageObjectPath,
            warrantyEndDate: event.endDate,
            items: s.detail.items,
          ),
          clearTransient: true,
        ),
      ),
    );
  }
}
