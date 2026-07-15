import 'package:flutter/material.dart';

import 'package:smartspend/l10n/generated/app_localizations.dart';

/// One-time consent ask before the first scan (App Store 5.1.1(i)/5.1.2(i)):
/// explains that the receipt photo — and nothing else — may be sent to
/// Google Gemini when on-device OCR falls short, and that declining keeps
/// scanning fully on-device.
///
/// Returns `true` (allow) or `false` (deny); the barrier is not dismissible
/// so the user always makes an explicit choice.
Future<bool> showScanAiConsentDialog(BuildContext context) async {
  final bool? granted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => const ScanAiConsentDialog(),
  );
  return granted ?? false;
}

class ScanAiConsentDialog extends StatelessWidget {
  const ScanAiConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(
        Icons.auto_awesome_rounded,
        color: theme.colorScheme.primary,
      ),
      title: Text(l.scanAiConsentTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.scanAiConsentBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(l.scanAiConsentHint, style: theme.textTheme.bodySmall),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.scanAiConsentDeny),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.scanAiConsentAllow),
        ),
      ],
    );
  }
}
