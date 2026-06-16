part of 'receipt_archive_bloc.dart';

sealed class ReceiptArchiveEvent extends Equatable {
  const ReceiptArchiveEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Page mount — subscribe to the empty-filter archive stream.
final class ReceiptArchiveSubscribed extends ReceiptArchiveEvent {
  const ReceiptArchiveSubscribed();
}

/// Search input changed. Debounced by the event transformer (300ms) so
/// the underlying stream doesn't get re-subscribed on every keystroke.
final class ReceiptArchiveSearchChanged extends ReceiptArchiveEvent {
  const ReceiptArchiveSearchChanged({required this.query});

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}

/// Filter date range changed. Either bound may be null (open).
final class ReceiptArchiveDateRangeChanged extends ReceiptArchiveEvent {
  const ReceiptArchiveDateRangeChanged({this.from, this.to});

  final DateTime? from;
  final DateTime? to;

  @override
  List<Object?> get props => <Object?>[from, to];
}

/// Toggle grid / list view. Pure UI state, but kept on the bloc so
/// rotating the device or popping back to the page restores the user's
/// last choice.
final class ReceiptArchiveViewToggled extends ReceiptArchiveEvent {
  const ReceiptArchiveViewToggled();
}

/// Private — fires when the upstream Drift stream emits.
final class _ReceiptArchiveTicked extends ReceiptArchiveEvent {
  const _ReceiptArchiveTicked(this.entries);

  final List<ReceiptArchiveEntry> entries;

  @override
  List<Object?> get props => <Object?>[entries];
}

/// Private — fires when the Drift stream emits an error.
final class _ReceiptArchiveStreamErrored extends ReceiptArchiveEvent {
  const _ReceiptArchiveStreamErrored(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
