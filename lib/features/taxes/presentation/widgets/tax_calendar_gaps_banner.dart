import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/core/market/tax/tax_calendar_generator.dart';
import 'package:smartspend/features/taxes/presentation/tax_labels.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// What the generator declined to produce, and why.
///
/// The generator refuses to invent a recurrence for an obligation whose
/// deciding question the user skipped — defaulting VAT to monthly would put
/// eleven imagined deadlines a year in front of someone who never said they
/// file it. But refusing silently would leave the user believing their
/// calendar is complete, which is the same lie by omission.
///
/// So the gaps are shown, named, and given the one action that closes them.
class TaxCalendarGapsBanner extends StatelessWidget {
  const TaxCalendarGapsBanner({required this.gaps, super.key});

  /// The obligations that could not be generated.
  final List<TaxCalendarGap> gaps;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Card(
      key: const Key('tax.calendar.gaps'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.taxCalendarGapsTitle(gaps.length),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l.taxCalendarGapsBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // Naming them is the point. "Some items are missing" tells the
            // user nothing they can act on; "KDV beyannamesi is missing"
            // tells them exactly which answer to go back and give.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: gaps
                  .map(
                    (TaxCalendarGap gap) => Chip(
                      label: Text(taxObligationName(l, gap.kind)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('tax.calendar.gaps.action'),
                onPressed: () => context.push('/taxes/profile'),
                child: Text(l.taxCalendarGapsAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
