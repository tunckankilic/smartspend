import 'package:flutter/material.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_circular_progress.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_tone_color.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Large hero card for the general (uncategorised) budget.
///
/// Shows a custom-painted circular progress + spent/total/remaining
/// labels. Tap → invokes [onTap] (the page wires this to the edit
/// sheet).
class BudgetGeneralCard extends StatelessWidget {
  const BudgetGeneralCard({
    required this.snapshot,
    required this.onTap,
    super.key,
  });

  final BudgetSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final String currency = snapshot.budget.currency;
    final int percent = (snapshot.status.percentSpent * 100).round();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    l.budgetGeneralLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: budgetToneColor(
                        snapshot.status.tone,
                        dim: true,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _periodLabel(l, snapshot.budget.period),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: budgetToneColor(snapshot.status.tone),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: BudgetCircularProgress(
                  percentSpent: snapshot.status.percentSpent,
                  tone: snapshot.status.tone,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l.budgetPercentSpent(percent.toString()),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMinor(
                          snapshot.status.spentMinor,
                          currency,
                          locale: locale,
                        ),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    l.budgetSpentOfTotal(
                      formatMinor(
                        snapshot.status.spentMinor,
                        currency,
                        locale: locale,
                      ),
                      formatMinor(
                        snapshot.status.amountMinor,
                        currency,
                        locale: locale,
                      ),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    snapshot.status.isExceeded
                        ? l.budgetOverspent(
                            formatMinor(
                              -snapshot.status.remainingMinor,
                              currency,
                              locale: locale,
                            ),
                          )
                        : l.budgetRemaining(
                            formatMinor(
                              snapshot.status.remainingMinor,
                              currency,
                              locale: locale,
                            ),
                          ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: budgetToneColor(snapshot.status.tone),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _periodLabel(AppLocalizations l, BudgetPeriod p) {
    return switch (p) {
      BudgetPeriod.weekly => l.budgetPeriodWeekly,
      BudgetPeriod.monthly => l.budgetPeriodMonthly,
      BudgetPeriod.yearly => l.budgetPeriodYearly,
    };
  }
}
