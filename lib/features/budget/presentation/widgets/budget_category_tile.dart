import 'package:flutter/material.dart';

import 'package:smartspend/core/utils/category_display_name.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/domain/entities/budget_status.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_tone_color.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// One row per category-targeted budget. Linear progress + the same
/// 4-tone color map as the general card.
class BudgetCategoryTile extends StatelessWidget {
  const BudgetCategoryTile({
    required this.snapshot,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final BudgetSnapshot snapshot;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final String currency = snapshot.budget.currency;
    final BudgetStatus status = snapshot.status;
    final Color toneColor = budgetToneColor(status.tone);
    final Color trackColor = budgetToneColor(status.tone, dim: true);
    final int percent = (status.percentSpent * 100).round();

    return Dismissible(
      key: ValueKey<int>(snapshot.budget.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (DismissDirection _) {
        return showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(l.budgetDeleteConfirmTitle),
            content: Text(l.budgetDeleteConfirmBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.budgetDeleteCancel),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.budgetDeleteConfirm),
              ),
            ],
          ),
        );
      },
      onDismissed: (DismissDirection _) => onDelete(),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: snapshot.category == null
                            ? trackColor
                            : Color(
                                snapshot.category!.color,
                              ).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        snapshot.category == null
                            ? Icons.account_balance_wallet_rounded
                            : iconForCategory(snapshot.category!.icon),
                        color: snapshot.category == null
                            ? toneColor
                            : Color(snapshot.category!.color),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        snapshot.category == null
                            ? l.budgetGeneralLabel
                            : localizedCategoryName(l, snapshot.category!),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      l.budgetPercentSpent(percent.toString()),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: toneColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: status.percentSpent.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: trackColor,
                    valueColor: AlwaysStoppedAnimation<Color>(toneColor),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      l.budgetSpentOfTotal(
                        formatMinor(
                          status.spentMinor,
                          currency,
                          locale: locale,
                        ),
                        formatMinor(
                          status.amountMinor,
                          currency,
                          locale: locale,
                        ),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      status.isExceeded
                          ? l.budgetOverspent(
                              formatMinor(
                                -status.remainingMinor,
                                currency,
                                locale: locale,
                              ),
                            )
                          : l.budgetRemaining(
                              formatMinor(
                                status.remainingMinor,
                                currency,
                                locale: locale,
                              ),
                            ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: toneColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
