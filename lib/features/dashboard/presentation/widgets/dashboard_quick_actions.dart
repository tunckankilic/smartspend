import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Four square buttons under the period chips: Scan / Add / Budget /
/// Report. Tappable feedback uses [InkWell]; layout is a horizontal Row
/// of [Expanded] tiles so phones get equal width without overflow.
class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuickActionTile(
            key: const ValueKey<String>('quickAction.scan'),
            icon: Icons.qr_code_scanner_rounded,
            label: l.dashboardQuickActionScan,
            onTap: () => context.go('/scan'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickActionTile(
            key: const ValueKey<String>('quickAction.add'),
            icon: Icons.add_rounded,
            label: l.dashboardQuickActionAdd,
            onTap: () => context.push('/expenses/new'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickActionTile(
            key: const ValueKey<String>('quickAction.budget'),
            icon: Icons.savings_rounded,
            label: l.dashboardQuickActionBudget,
            onTap: () => context.go('/budget'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickActionTile(
            key: const ValueKey<String>('quickAction.report'),
            icon: Icons.insights_rounded,
            label: l.dashboardQuickActionReport,
            // Report = a CSV/PDF export of the user's expenses. The export
            // actions live on the Settings tab; jump there.
            onTap: () => context.go('/settings'),
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: cs.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
