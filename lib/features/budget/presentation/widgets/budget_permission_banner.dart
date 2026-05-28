import 'package:flutter/material.dart';

import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Top-of-page banner shown when the user hasn't granted notification
/// permission. Tapping the action button fires
/// `BudgetPermissionRequested` on the bloc; the page handles the wiring.
class BudgetPermissionBanner extends StatelessWidget {
  const BudgetPermissionBanner({
    required this.onRequest,
    super.key,
  });

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.7),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.notifications_off_rounded,
                color: cs.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.budgetPermissionBannerTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: cs.onErrorContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.budgetPermissionBannerBody,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onErrorContainer),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onRequest,
                child: Text(l.budgetPermissionBannerAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
