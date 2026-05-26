import 'package:flutter/material.dart';

import 'package:smartspend/core/widgets/placeholder_screen.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return PlaceholderScreen(
      title: l.navDashboard,
      message: l.placeholderDashboard,
      icon: Icons.dashboard_rounded,
    );
  }
}
