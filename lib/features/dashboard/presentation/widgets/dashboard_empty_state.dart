import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Shown in the page body when the selected period has no expenses.
class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.receipt_long_rounded,
            size: 64,
            color: cs.outline,
          ),
          const SizedBox(height: 12),
          Text(
            l.dashboardEmptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l.dashboardEmptyBody,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => context.go('/scan'),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(l.dashboardQuickActionScan),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/expenses/new'),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.dashboardQuickActionAdd),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
