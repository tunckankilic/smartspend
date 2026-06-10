import 'package:flutter/material.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_window.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Wireframe 04's triple summary strip — Budget / Spent / Days Left as
/// three equal cards above the general budget hero card.
///
/// Rendered only when a general budget exists; per-category budgets have
/// their own tiles and summing mixed periods would be misleading.
class BudgetSummaryRow extends StatelessWidget {
  const BudgetSummaryRow({required this.snapshot, super.key});

  /// The general (uncategorised) budget snapshot.
  final BudgetSnapshot snapshot;

  /// Whole days from [now] until the end of [window], never negative.
  ///
  /// The window end is exclusive midnight UTC, so "ends tonight" counts
  /// as 1 — matching the wireframe's "7 gün" human framing.
  static int daysLeft(BudgetWindow window, DateTime now) {
    final Duration left = window.endUtcExclusive.difference(now.toUtc());
    if (left.isNegative) return 0;
    return (left.inHours / 24).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final String currency = snapshot.budget.currency;
    final int days = daysLeft(snapshot.window, DateTime.now());

    return Row(
      children: <Widget>[
        Expanded(
          child: _SummaryCard(
            label: l.budgetSummaryBudgetLabel,
            value: formatMinorCompact(
              snapshot.status.amountMinor,
              currency,
              locale: locale,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: l.budgetSummarySpentLabel,
            value: formatMinorCompact(
              snapshot.status.spentMinor,
              currency,
              locale: locale,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: l.budgetSummaryDaysLeftLabel,
            value: l.budgetSummaryDaysValue(days),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
