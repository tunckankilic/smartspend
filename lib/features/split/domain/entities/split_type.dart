/// How a receipt is divided across participants (Sprint 7).
enum SplitType {
  /// Total of the receipt is divided equally among **every** participant,
  /// regardless of item assignments. Per-item assignments are ignored
  /// while this mode is active.
  equal,

  /// Each item is owned by whoever it's assigned to. When more than one
  /// participant is assigned to a single item, that item's total is
  /// divided equally between them. Items without any assignment are
  /// shared equally across all participants — matches how restaurant
  /// bills are usually settled (drinks for the table, etc.).
  custom;

  /// Returns the enum matching [name], or `null` if unknown.
  static SplitType? fromName(String name) {
    for (final SplitType v in SplitType.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
