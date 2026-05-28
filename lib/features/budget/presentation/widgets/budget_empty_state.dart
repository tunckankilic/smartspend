import 'package:flutter/material.dart';

import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Renders when the user has zero active budgets. Tapping the CTA
/// fires the same "open create sheet" callback the FAB does, so the
/// page can route both into a single handler.
class BudgetEmptyState extends StatelessWidget {
  const BudgetEmptyState({
    required this.onCreate,
    super.key,
  });

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.savings_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            l.budgetEmptyTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l.budgetEmptyBody,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: Text(l.budgetEmptyCta),
          ),
        ],
      ),
    );
  }
}
