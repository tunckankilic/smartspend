part of 'split_bloc.dart';

/// Inputs accepted by [SplitBloc] (Sprint 7).
sealed class SplitEvent extends Equatable {
  const SplitEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Page mount — load the receipt into a fresh `SplitSession`.
final class SplitStarted extends SplitEvent {
  const SplitStarted({required this.receiptId});

  final int receiptId;

  @override
  List<Object?> get props => <Object?>[receiptId];
}

/// Add a participant by display name. Trimmed by the bloc.
final class SplitParticipantAdded extends SplitEvent {
  const SplitParticipantAdded({required this.name});

  final String name;

  @override
  List<Object?> get props => <Object?>[name];
}

/// Remove a participant by id. Their assignments are scrubbed from
/// every item.
final class SplitParticipantRemoved extends SplitEvent {
  const SplitParticipantRemoved({required this.participantId});

  final String participantId;

  @override
  List<Object?> get props => <Object?>[participantId];
}

/// Replace the assignment set for a single item.
///
/// Empty list ⇒ item becomes "unassigned" (shared by everyone in
/// custom mode).
final class SplitItemAssigned extends SplitEvent {
  const SplitItemAssigned({
    required this.itemId,
    required this.participantIds,
  });

  final int itemId;
  final List<String> participantIds;

  @override
  List<Object?> get props => <Object?>[itemId, participantIds];
}

/// Toggle between equal / custom split modes.
final class SplitTypeChanged extends SplitEvent {
  const SplitTypeChanged({required this.type});

  final SplitType type;

  @override
  List<Object?> get props => <Object?>[type];
}

/// Hand a prebuilt share-sheet payload to the share sink.
///
/// The payload is composed at the presentation layer (by
/// `ShareSplitFormatter.format`) so the bloc keeps a Flutter-free
/// signature. The sink is platform-specific (`share_plus` in
/// production); tests inject a fake.
final class SplitShareRequested extends SplitEvent {
  const SplitShareRequested({required this.payload});

  final String payload;

  @override
  List<Object?> get props => <Object?>[payload];
}
