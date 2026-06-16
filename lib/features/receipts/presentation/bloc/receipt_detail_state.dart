part of 'receipt_detail_bloc.dart';

sealed class ReceiptDetailState extends Equatable {
  const ReceiptDetailState();

  @override
  List<Object?> get props => const <Object?>[];
}

final class ReceiptDetailInitial extends ReceiptDetailState {
  const ReceiptDetailInitial();
}

final class ReceiptDetailLoading extends ReceiptDetailState {
  const ReceiptDetailLoading();
}

final class ReceiptDetailReady extends ReceiptDetailState {
  const ReceiptDetailReady({
    required this.detail,
    this.signedImageUrl,
    this.transientFailure,
    this.imageUnavailable = false,
  });

  final ReceiptDetail detail;

  /// Signed Supabase Storage URL, resolved lazily after load when the
  /// local image file is gone. `null` until resolved (or if unavailable).
  final String? signedImageUrl;
  final Failure? transientFailure;

  /// True when the receipt has a remote image but neither the local cache
  /// nor the signed-URL fallback could produce it. Drives the
  /// `storageImageMissing` notice in the UI.
  final bool imageUnavailable;

  ReceiptDetailReady copyWith({
    ReceiptDetail? detail,
    String? signedImageUrl,
    Failure? transientFailure,
    bool clearTransient = false,
    bool? imageUnavailable,
  }) {
    return ReceiptDetailReady(
      detail: detail ?? this.detail,
      signedImageUrl: signedImageUrl ?? this.signedImageUrl,
      transientFailure:
          clearTransient ? null : (transientFailure ?? this.transientFailure),
      imageUnavailable: imageUnavailable ?? this.imageUnavailable,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[detail, signedImageUrl, transientFailure, imageUnavailable];
}

final class ReceiptDetailError extends ReceiptDetailState {
  const ReceiptDetailError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
