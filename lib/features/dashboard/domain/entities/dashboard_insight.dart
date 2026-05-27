import 'package:equatable/equatable.dart';

/// Banner payload surfaced above the recent-expenses list when a
/// noteworthy spending pattern is detected.
///
/// Sprint 5 ships exactly one rule (category-level spike vs the previous
/// period). The shape leaves room for Sprint 6 to add achievement /
/// savings-tip variants — bump [DashboardInsightTone] and dispatch in
/// the widget switch.
class DashboardInsight extends Equatable {
  const DashboardInsight({
    required this.categoryId,
    required this.deltaPercent,
    required this.tone,
  });

  /// Category whose delta tripped the rule.
  final int categoryId;

  /// Signed percentage delta vs the previous period (positive = spent
  /// more this period).
  final double deltaPercent;

  final DashboardInsightTone tone;

  @override
  List<Object?> get props => <Object?>[categoryId, deltaPercent, tone];
}

enum DashboardInsightTone {
  /// Spending went up notably — orange.
  warning,

  /// Spending dropped — green. Reserved for future rules.
  positive,
}
