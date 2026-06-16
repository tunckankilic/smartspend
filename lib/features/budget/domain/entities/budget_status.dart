import 'package:equatable/equatable.dart';

/// Visual + semantic state of a budget at a point in time.
///
/// Maps the prompt's color spec:
///   * `healthy`  — < 50 % spent  (green)
///   * `warning`  — 50–80 %       (yellow)
///   * `danger`   — 80–100 %      (orange)
///   * `exceeded` — ≥ 100 %       (red)
enum BudgetTone { healthy, warning, danger, exceeded }

/// Output of [BudgetStatusCalculator].
///
/// Pure value object — given the same inputs, BLoC tests can assert on
/// the same outputs without touching Drift, ExpenseRepository, or any
/// platform plugin.
class BudgetStatus extends Equatable {
  const BudgetStatus({
    required this.spentMinor,
    required this.amountMinor,
    required this.percentSpent,
    required this.tone,
    required this.crossedThresholds,
  });

  /// Spent so far in minor units. Always non-negative.
  final int spentMinor;

  /// Budget cap in minor units (mirror of [Budget.amountMinor]).
  final int amountMinor;

  /// `spent / amount`. `0.0` for a zero-amount budget (defensive — the
  /// create use case rejects zero amounts but the calculator stays safe
  /// if a stale row sneaks in). Values `> 1.0` indicate overspend.
  final double percentSpent;

  final BudgetTone tone;

  /// Subset of [BudgetStatusCalculator.defaultThresholds] (or the caller-
  /// supplied list) whose levels have been reached. BLoC compares this
  /// across emissions to fire a notification only on a **new** crossing.
  final List<int> crossedThresholds;

  bool get isExceeded => tone == BudgetTone.exceeded;

  bool get isOnTrack => tone == BudgetTone.healthy;

  /// May be negative when the budget is exceeded.
  int get remainingMinor => amountMinor - spentMinor;

  @override
  List<Object?> get props => <Object?>[
        spentMinor,
        amountMinor,
        percentSpent,
        tone,
        crossedThresholds,
      ];
}

/// Pure-function computation: status from (spent, amount, thresholds).
///
/// Kept as static helpers so tests can call it directly without any
/// dependency-injection ceremony. The BLoC composes it on top of the
/// reactive Drift stream.
class BudgetStatusCalculator {
  const BudgetStatusCalculator._();

  /// Default notification thresholds (50/80/100 %).
  static const List<int> defaultThresholds = <int>[50, 80, 100];

  /// Compute the status snapshot.
  ///
  /// [spentMinor] is the total amount spent in the budget's current
  /// window. [amountMinor] is the budget cap. [thresholds] is the
  /// list of percentage triggers to track — pass `const []` to skip
  /// crossing detection entirely (useful in the Dashboard read path
  /// where the BLoC only renders progress, never fires notifications).
  static BudgetStatus calculate({
    required int spentMinor,
    required int amountMinor,
    List<int> thresholds = defaultThresholds,
  }) {
    final int safeSpent = spentMinor < 0 ? 0 : spentMinor;
    if (amountMinor <= 0) {
      return BudgetStatus(
        spentMinor: safeSpent,
        amountMinor: amountMinor,
        percentSpent: 0,
        tone: BudgetTone.healthy,
        crossedThresholds: const <int>[],
      );
    }
    final double percent = safeSpent / amountMinor;
    final BudgetTone tone;
    if (percent >= 1.0) {
      tone = BudgetTone.exceeded;
    } else if (percent >= 0.8) {
      tone = BudgetTone.danger;
    } else if (percent >= 0.5) {
      tone = BudgetTone.warning;
    } else {
      tone = BudgetTone.healthy;
    }
    final List<int> crossed = <int>[
      for (final int t in thresholds)
        if (percent * 100 >= t) t,
    ];
    return BudgetStatus(
      spentMinor: safeSpent,
      amountMinor: amountMinor,
      percentSpent: percent,
      tone: tone,
      crossedThresholds: crossed,
    );
  }
}
