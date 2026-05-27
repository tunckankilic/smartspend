import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Compact list of up to 5 recent expenses with a "See all" action.
class DashboardRecentList extends StatelessWidget {
  const DashboardRecentList({
    required this.expenses,
    required this.locale,
    super.key,
  });

  final List<Expense> expenses;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < expenses.length; i++) ...<Widget>[
            _RecentTile(
              expense: expenses[i],
              locale: locale,
            ),
            if (i < expenses.length - 1)
              const Divider(height: 1, indent: 64, endIndent: 16),
          ],
          TextButton.icon(
            onPressed: () => context.go('/expenses'),
            icon: const Icon(Icons.list_alt_rounded),
            label: Text(l.dashboardRecentSeeAll),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.expense, required this.locale});

  final Expense expense;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final Color catColor = Color(expense.category.color);
    return ListTile(
      onTap: () => context.go('/expenses/${expense.id}'),
      leading: CircleAvatar(
        backgroundColor: catColor.withValues(alpha: 0.18),
        foregroundColor: catColor,
        child: Icon(iconForCategory(expense.category.icon)),
      ),
      title: Text(
        expense.note?.isNotEmpty == true
            ? expense.note!
            : expense.category.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(DateFormat.MMMd(locale).format(expense.date.toLocal())),
      trailing: Text(
        formatMinor(expense.amount, expense.currency, locale: locale),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
