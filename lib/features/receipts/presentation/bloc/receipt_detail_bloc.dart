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
  })  : _getDetail = getDetail,
        _addWarranty = addWarranty,
        super(const ReceiptDetailInitial()) {
    on<ReceiptDetailLoaded>(_onLoaded, transformer: droppable());
    on<ReceiptWarrantyChanged>(_onWarrantyChanged, transformer: sequential());
  }

  final GetReceiptDetailUseCase _getDetail;
  final AddWarrantyUseCase _addWarranty;

  Future<void> _onLoaded(
    ReceiptDetailLoaded event,
    Emitter<ReceiptDetailState> emit,
  ) async {
    emit(const ReceiptDetailLoading());
    final Either<Failure, ReceiptDetail> result =
        await _getDetail(GetReceiptDetailParams(receiptId: event.receiptId));
    result.fold(
      (Failure f) => emit(ReceiptDetailError(failure: f)),
      (ReceiptDetail d) => emit(ReceiptDetailReady(detail: d)),
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
            warrantyEndDate: event.endDate,
            items: s.detail.items,
          ),
          clearTransient: true,
        ),
      ),
    );
  }
}
