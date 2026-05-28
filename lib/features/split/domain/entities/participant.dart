import 'package:equatable/equatable.dart';

/// A person sharing a receipt's cost in a SplitSession (Sprint 7).
///
/// Participants are **session-local**: they live only inside the
/// in-memory `SplitSession` and are not persisted to Drift / Supabase.
/// Identity is a synthetic string id assigned by `SplitBloc` on add
/// (typically `p1`, `p2`, ...). When/if we promote split to a
/// persisted feature (Sprint 8 candidate) this id space migrates to a
/// uuid backed by `split_sessions.participants`.
class Participant extends Equatable {
  const Participant({required this.id, required this.name});

  /// Synthetic id stable within a single SplitSession's lifetime.
  final String id;

  /// Display name as typed by the user. Trimmed by the BLoC before
  /// arriving here.
  final String name;

  @override
  List<Object?> get props => <Object?>[id, name];
}
