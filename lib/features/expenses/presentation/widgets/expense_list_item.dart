import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// One row in the expense list.
///
/// Wraps the row in a [Dismissible] so the parent can wire swipe-to-delete
/// without re-implementing the visual.
class ExpenseListItem extends StatelessWidget {
  const ExpenseListItem({
    required this.expense,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final Expense expense;
  final VoidCallback onTap;

  /// Called after the user confirms the swipe gesture.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final Color tint = Color(expense.category.color);
    final DateFormat dayFormat =
        DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag());
    final String dayLabel = dayFormat.format(expense.date.toLocal());

    return Dismissible(
      key: ValueKey<int>(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.onError,
        ),
      ),
      confirmDismiss: (_) async {
        final bool? answer = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(l.expenseListDeleteTitle),
            content: Text(l.expenseListDeleteBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.editCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.expenseListDeleteConfirm),
              ),
            ],
          ),
        );
        return answer ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tint.withValues(alpha: 0.18),
          foregroundColor: tint,
          child: Icon(iconForCategory(expense.category.icon)),
        ),
        title: Text(
          expense.note?.isNotEmpty == true
              ? expense.note!
              : expense.category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: <Widget>[
            Text(
              expense.category.name,
              style: theme.textTheme.bodySmall,
            ),
            Text(' · ', style: theme.textTheme.bodySmall),
            Text(dayLabel, style: theme.textTheme.bodySmall),
            if (expense.isPendingSync) ...<Widget>[
              const SizedBox(width: 6),
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: theme.colorScheme.outline,
                semanticLabel: l.expenseListPendingSync,
              ),
            ],
            if (expense.isRecurring) ...<Widget>[
              const SizedBox(width: 6),
              Icon(
                Icons.autorenew_rounded,
                size: 14,
                color: theme.colorScheme.outline,
                semanticLabel: l.expenseListRecurring,
              ),
            ],
          ],
        ),
        trailing: Text(
          formatMinor(
            expense.amount,
            expense.currency,
            locale: Localizations.localeOf(context).toLanguageTag(),
          ),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
