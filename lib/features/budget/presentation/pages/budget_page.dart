import 'package:flutter/material.dart';

import 'package:smartspend/core/widgets/placeholder_screen.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class BudgetPage extends StatelessWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return PlaceholderScreen(
      title: l.navBudget,
      message: l.placeholderBudget,
      icon: Icons.pie_chart_rounded,
    );
  }
}
