import 'package:flutter/material.dart';

import 'package:smartspend/core/widgets/placeholder_screen.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class ExpenseListPage extends StatelessWidget {
  const ExpenseListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return PlaceholderScreen(
      title: l.navExpenses,
      message: l.placeholderExpenses,
      icon: Icons.receipt_long_rounded,
    );
  }
}
