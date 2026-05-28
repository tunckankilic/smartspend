part of 'receipt_archive_bloc.dart';

/// Toggle between grid (default) and list views in the archive page.
enum ReceiptArchiveLayout { grid, list }

sealed class ReceiptArchiveState extends Equatable {
  const ReceiptArchiveState();

  @override
  List<Object?> get props => const <Object?>[];
}

final class ReceiptArchiveInitial extends ReceiptArchiveState {
  const ReceiptArchiveInitial();
}

final class ReceiptArchiveLoading extends ReceiptArchiveState {
  const ReceiptArchiveLoading();
}

/// Steady state — at least one stream tick has landed. [entries] may be
/// empty (no receipts at all, or filters too restrictive) — the UI
/// distinguishes these via [filter.isEmpty].
final class ReceiptArchiveLoaded extends ReceiptArchiveState {
  const ReceiptArchiveLoaded({
    required this.entries,
    required this.filter,
    required this.layout,
  });

  final List<ReceiptArchiveEntry> entries;
  final ReceiptArchiveFilter filter;
  final ReceiptArchiveLayout layout;

  ReceiptArchiveLoaded copyWith({
    List<ReceiptArchiveEntry>? entries,
    ReceiptArchiveFilter? filter,
    ReceiptArchiveLayout? layout,
  }) {
    return ReceiptArchiveLoaded(
      entries: entries ?? this.entries,
      filter: filter ?? this.filter,
      layout: layout ?? this.layout,
    );
  }

  @override
  List<Object?> get props => <Object?>[entries, filter, layout];
}

final class ReceiptArchiveError extends ReceiptArchiveState {
  const ReceiptArchiveError({required this.failure});

  final Failure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}
