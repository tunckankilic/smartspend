import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/presentation/tax_labels.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// One row of the tax calendar.
///
/// Two deadlines get two lines, always — including when one of them is
/// absent, which is shown as "no filing step" rather than left blank. A blank
/// line reads as missing data; the statement reads as the fact it is, and
/// five of the fourteen Turkish obligations only have one side.
///
/// The date warning is the card's normal state, not an exception: every
/// catalog rule is unverified today, so every generated item carries it. It is
/// therefore a quiet inline note rather than an alarm — an alarm on every row
/// is an alarm nobody reads.
class TaxObligationCard extends StatelessWidget {
  const TaxObligationCard({
    required this.item,
    required this.today,
    this.onTap,
    super.key,
  });

  /// The item to render.
  final TaxCalendarItem item;

  /// The day the state is derived against. Passed in rather than read from a
  /// clock so the card is a pure function of its inputs.
  final DateTime today;

  /// Opens the detail screen.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TaxObligationState state = item.stateAt(today);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      taxItemName(l, item),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  _StateChip(state: state),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _periodLabel(context, l),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _DeadlineLine(
                label: l.taxItemDeclarationDue,
                date: item.declarationDueDate,
                exists: item.hasDeclarationStep,
                absentLabel: l.taxItemNoDeclaration,
                done: item.declaredAt != null,
              ),
              const SizedBox(height: 4),
              _DeadlineLine(
                label: l.taxItemPaymentDue,
                date: item.paymentDueDate,
                exists: item.hasPaymentStep,
                absentLabel: l.taxItemNoPayment,
                done: item.paidAt != null,
              ),
              if (item.isConditional) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  l.taxItemConditional,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (item.needsDateWarning) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.taxItemDateWarning,
                        key: const Key('tax.card.dateWarning'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _periodLabel(BuildContext context, AppLocalizations l) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final String period = DateFormat.yMMMM(locale).format(item.periodStart);
    if (item.installmentIndex == 0) {
      return period;
    }
    return '$period · ${l.taxItemInstallment(item.installmentIndex)}';
  }
}

/// One deadline, stated even when it does not exist.
class _DeadlineLine extends StatelessWidget {
  const _DeadlineLine({
    required this.label,
    required this.date,
    required this.exists,
    required this.absentLabel,
    required this.done,
  });

  final String label;
  final DateTime? date;
  final bool exists;
  final String absentLabel;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();

    // Three different things, deliberately worded differently: the step does
    // not exist, the step exists but we have no confirmed date, or here is
    // the date.
    final String value = !exists
        ? absentLabel
        : date == null
            ? l.taxItemDateMissing
            : DateFormat.yMMMd(locale).format(date!);

    return Row(
      children: <Widget>[
        if (done)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.check,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              decoration: done ? TextDecoration.lineThrough : null,
              color: exists ? null : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The derived-state badge.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final TaxObligationState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Color background = switch (state) {
      TaxObligationState.overdue => scheme.errorContainer,
      TaxObligationState.dueToday => scheme.tertiaryContainer,
      TaxObligationState.completed => scheme.secondaryContainer,
      TaxObligationState.dismissed ||
      TaxObligationState.undated ||
      TaxObligationState.upcoming =>
        scheme.surfaceContainerHighest,
    };
    final Color foreground = switch (state) {
      TaxObligationState.overdue => scheme.onErrorContainer,
      TaxObligationState.dueToday => scheme.onTertiaryContainer,
      TaxObligationState.completed => scheme.onSecondaryContainer,
      TaxObligationState.dismissed ||
      TaxObligationState.undated ||
      TaxObligationState.upcoming =>
        scheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        taxStateLabel(l, state),
        key: const Key('tax.card.state'),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}
