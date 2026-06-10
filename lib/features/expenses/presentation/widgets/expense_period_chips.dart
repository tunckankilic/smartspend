import 'package:flutter/material.dart';

import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Preset date ranges surfaced as a chip row on top of the expense list —
/// the wireframe's "Bu Hafta / Bu Ay / 3 Ay" shortcut bar. Deeper filters
/// (categories, amounts, custom ranges) stay in the filter sheet.
enum ExpenseListPeriod {
  /// No date bounds at all.
  all,

  /// From Monday of the current week.
  thisWeek,

  /// From the 1st of the current month.
  thisMonth,

  /// From the 1st of the month two months back (a rolling ~3 month view).
  last3Months,
}

/// Single-select chip row that rewrites the [ExpenseFilter] date bounds.
///
/// Selection is derived from the filter itself (no local state): a chip is
/// highlighted when `dateFrom` matches its canonical range start and
/// `dateTo` is unset. A custom range picked in the filter sheet therefore
/// leaves every chip unselected — which is the honest answer.
class ExpensePeriodChips extends StatelessWidget {
  const ExpensePeriodChips({
    required this.filter,
    required this.onChanged,
    super.key,
  });

  final ExpenseFilter filter;
  final ValueChanged<ExpenseFilter> onChanged;

  /// Canonical start date for [period], at local midnight. `null` for
  /// [ExpenseListPeriod.all].
  static DateTime? startOf(ExpenseListPeriod period, DateTime now) {
    return switch (period) {
      ExpenseListPeriod.all => null,
      ExpenseListPeriod.thisWeek => DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - 1),
      ),
      ExpenseListPeriod.thisMonth => DateTime(now.year, now.month),
      ExpenseListPeriod.last3Months => DateTime(now.year, now.month - 2),
    };
  }

  /// Which preset (if any) [filter] currently represents.
  static ExpenseListPeriod? periodOf(ExpenseFilter filter, DateTime now) {
    if (filter.dateTo != null) return null;
    if (filter.dateFrom == null) return ExpenseListPeriod.all;
    for (final ExpenseListPeriod p in <ExpenseListPeriod>[
      ExpenseListPeriod.thisWeek,
      ExpenseListPeriod.thisMonth,
      ExpenseListPeriod.last3Months,
    ]) {
      if (filter.dateFrom == startOf(p, now)) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime now = DateTime.now();
    final ExpenseListPeriod? selected = periodOf(filter, now);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          for (final ExpenseListPeriod p
              in ExpenseListPeriod.values) ...<Widget>[
            ChoiceChip(
              key: ValueKey<String>('expensePeriod.${p.name}'),
              label: Text(_label(l, p)),
              selected: selected == p,
              onSelected: (bool v) {
                if (!v) return;
                final DateTime? from = startOf(p, now);
                onChanged(
                  filter.copyWith(
                    dateFrom: from,
                    clearDateFrom: from == null,
                    clearDateTo: true,
                  ),
                );
              },
            ),
            if (p != ExpenseListPeriod.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  String _label(AppLocalizations l, ExpenseListPeriod p) {
    return switch (p) {
      ExpenseListPeriod.all => l.expenseListPeriodAll,
      ExpenseListPeriod.thisWeek => l.expenseListPeriodWeek,
      ExpenseListPeriod.thisMonth => l.expenseListPeriodMonth,
      ExpenseListPeriod.last3Months => l.expenseListPeriod3Months,
    };
  }
}
