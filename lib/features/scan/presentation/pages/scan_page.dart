import 'package:flutter/material.dart';

import 'package:smartspend/core/widgets/placeholder_screen.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class ScanPage extends StatelessWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return PlaceholderScreen(
      title: l.navScan,
      message: l.placeholderScan,
      icon: Icons.camera_alt_rounded,
    );
  }
}
