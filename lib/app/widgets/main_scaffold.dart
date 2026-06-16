import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Wraps every tab route inside the shell.
///
/// Renders a custom bottom navigation bar with the centre "Scan" action
/// raised like a FAB. Tab order matches the GoRouter `StatefulShellRoute`
/// branches: dashboard, expenses, scan (center), budget, settings.
class MainScaffold extends StatelessWidget {
  const MainScaffold({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    final List<_NavItem> items = <_NavItem>[
      _NavItem(
        icon: Icons.dashboard_rounded,
        label: l.navDashboard,
      ),
      _NavItem(
        icon: Icons.receipt_long_rounded,
        label: l.navExpenses,
      ),
      _NavItem(
        icon: Icons.camera_alt_rounded,
        label: l.navScan,
        isHighlighted: true,
      ),
      _NavItem(
        icon: Icons.pie_chart_rounded,
        label: l.navBudget,
      ),
      _NavItem(
        icon: Icons.settings_rounded,
        label: l.navSettings,
      ),
    ];

    return Scaffold(
      body: BlocListener<SyncCubit, SyncState>(
        listenWhen: (SyncState p, SyncState c) => c is SyncConflict,
        listener: (BuildContext context, SyncState state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(l.syncConflictBanner)),
            );
        },
        child: navigationShell,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List<Widget>.generate(items.length, (int i) {
              final _NavItem item = items[i];
              final bool selected = navigationShell.currentIndex == i;
              return Expanded(
                child: _NavButton(
                  item: item,
                  selected: selected,
                  onTap: () => _onTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
    this.isHighlighted = false,
  });

  final IconData icon;
  final String label;
  final bool isHighlighted;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tint = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);

    if (item.isHighlighted) {
      return Center(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(item.icon, color: theme.colorScheme.onPrimary),
          ),
        ),
      );
    }

    return InkResponse(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(item.icon, color: tint),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: theme.textTheme.labelSmall?.copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}
