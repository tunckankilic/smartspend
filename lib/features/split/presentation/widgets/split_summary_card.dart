import 'package:flutter/material.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// "Who owes what" summary at the bottom of `SplitPage`.
///
/// Pure leaf widget — receives the precomputed totals map and the
/// session. No bloc lookup, no math.
class SplitSummaryCard extends StatelessWidget {
  const SplitSummaryCard({
    required this.session,
    required this.perPersonMinor,
    super.key,
  });

  final SplitSession session;
  final Map<String, int> perPersonMinor;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.splitSummaryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (session.participants.isEmpty)
              Text(
                l.splitSummaryEmpty,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...<Widget>[
              for (final Participant p in session.participants)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(p.name)),
                      Text(
                        formatMinor(
                          perPersonMinor[p.id] ?? 0,
                          session.currency,
                          locale: locale,
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.splitSummaryTotal,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    formatMinor(
                      session.totalMinor,
                      session.currency,
                      locale: locale,
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
