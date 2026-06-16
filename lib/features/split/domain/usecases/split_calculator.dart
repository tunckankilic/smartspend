import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';

/// Pure-function engine that turns a SplitSession's raw inputs into
/// per-participant totals in minor units (Sprint 7).
///
/// Treated as the analogue of `BudgetStatusCalculator` (Sprint 6) — the
/// BLoC delegates the math here so the rules are unit-testable without
/// spinning up Flutter / Drift / Supabase.
///
/// Output contract:
///   * The returned map has **exactly one entry per participant**.
///   * Values are non-negative integers (minor units).
///   * Sum of all values equals [totalMinor] within ±N kuruş, where N is
///     the number of independent rounding buckets that ran (one per
///     unassigned item + one per multi-assigned item + one for the
///     equal-split bucket). The "remainder" cents are distributed
///     deterministically to the **first** participants (stable order)
///     so the same inputs always produce the same outputs.
class SplitCalculator {
  const SplitCalculator._();

  /// Calculates per-participant totals.
  ///
  /// Returns `{}` when [participants] is empty — the caller (UI) should
  /// guard the share button while this is true.
  ///
  /// When [type] is [SplitType.equal] the per-item [assignments] map is
  /// ignored and [totalMinor] is divided evenly. When [type] is
  /// [SplitType.custom] each item's price is allocated to its assigned
  /// participants; unassigned items fall back to "shared across all
  /// participants" (same allocation as equal split applied to that item
  /// alone). This matches restaurant-table behaviour where shared items
  /// like bread/drinks aren't tagged.
  static Map<String, int> calculate({
    required List<Participant> participants,
    required List<SplitItem> items,
    required Map<int, List<String>> assignments,
    required SplitType type,
    required int totalMinor,
  }) {
    if (participants.isEmpty) {
      return const <String, int>{};
    }
    final List<String> participantIds =
        participants.map((Participant p) => p.id).toList(growable: false);

    if (type == SplitType.equal) {
      return _divideEvenly(
        amountMinor: totalMinor,
        among: participantIds,
        seed: <String, int>{
          for (final String id in participantIds) id: 0,
        },
      );
    }

    // Custom split — walk each item, allocate to its assignees (or all
    // participants when unassigned), then aggregate.
    final Map<String, int> totals = <String, int>{
      for (final String id in participantIds) id: 0,
    };
    final Set<String> participantIdSet = participantIds.toSet();

    for (final SplitItem item in items) {
      final List<String>? raw = assignments[item.id];
      // Drop assignments to participants that have since been removed
      // — keeps the calculator resilient to ordering bugs in the bloc.
      final List<String> assignees = (raw ?? const <String>[])
          .where(participantIdSet.contains)
          .toList(growable: false);
      final List<String> bucket = assignees.isEmpty
          // Unassigned item → shared by everyone.
          ? participantIds
          : assignees;
      _distributeInto(
        sink: totals,
        amountMinor: item.totalPriceMinor,
        among: bucket,
      );
    }
    return totals;
  }

  // -------------------------------------------------------------------------
  // Internals — distribution with deterministic remainder allocation.
  // -------------------------------------------------------------------------

  /// Returns a fresh map with [amountMinor] split evenly across [among].
  /// Remainder cents go to the first N participants (in given order).
  static Map<String, int> _divideEvenly({
    required int amountMinor,
    required List<String> among,
    required Map<String, int> seed,
  }) {
    final Map<String, int> out = Map<String, int>.from(seed);
    _distributeInto(sink: out, amountMinor: amountMinor, among: among);
    return out;
  }

  /// Adds [amountMinor], divided evenly across [among], into [sink].
  /// Mutates [sink] in place. Stable: same inputs → same output.
  static void _distributeInto({
    required Map<String, int> sink,
    required int amountMinor,
    required List<String> among,
  }) {
    if (among.isEmpty || amountMinor == 0) {
      return;
    }
    final int n = among.length;
    final int base = amountMinor ~/ n;
    final int remainder = amountMinor - base * n; // 0..n-1, never negative.
    for (int i = 0; i < n; i++) {
      final String id = among[i];
      final int add = base + (i < remainder ? 1 : 0);
      sink[id] = (sink[id] ?? 0) + add;
    }
  }
}
