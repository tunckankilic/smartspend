import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_obligation_detail_cubit.dart';
import 'package:smartspend/features/taxes/presentation/tax_labels.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// One calendar item, with the two marks and the annotations (Block 4b, T8).
///
/// The two marks are two switches, never one. Filing and paying are separate
/// acts days apart, and an obligation can have only one of them — so a single
/// "done" control would be wrong for a third of the catalog and misleading
/// for the rest.
///
/// The amount field is the other place this screen is careful: it always
/// carries who said the number. There is no "calculated" option because
/// SmartSpend does not work tax out, and a figure the app produced would be
/// read as an amount to pay.
class TaxObligationDetailPage extends StatelessWidget {
  const TaxObligationDetailPage({required this.itemId, super.key});

  /// Local row id.
  final int itemId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TaxObligationDetailCubit>(
      create: (BuildContext _) => sl<TaxObligationDetailCubit>()..load(itemId),
      child: const _DetailView(),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);

    return BlocConsumer<TaxObligationDetailCubit, TaxObligationDetailState>(
      listenWhen: (
        TaxObligationDetailState a,
        TaxObligationDetailState b,
      ) =>
          a.failure != b.failure && b.failure != null,
      listener: (BuildContext context, TaxObligationDetailState state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.taxDetailSaveFailed)),
        );
      },
      builder: (BuildContext context, TaxObligationDetailState state) {
        final TaxCalendarItem? item = state.item;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              item == null ? l.taxDetailTitle : taxItemName(l, item),
            ),
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : item == null
                  ? Center(child: Text(l.taxDetailNotFound))
                  : _Body(item: item, today: state.today),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.item, required this.today});

  final TaxCalendarItem item;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TaxObligationDetailCubit cubit =
        context.read<TaxObligationDetailCubit>();
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final TaxObligationState state = item.stateAt(today);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Chip(
              key: const Key('tax.detail.state'),
              label: Text(taxStateLabel(l, state)),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Chip(
              key: const Key('tax.detail.dateSource'),
              label: Text(taxDueDateSourceLabel(l, item.dueDateSource)),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          DateFormat.yMMMM(locale).format(item.periodStart),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (item.needsDateWarning) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            key: const Key('tax.detail.dateWarning'),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.taxItemDateWarning,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Two deadlines, two marks. Never collapsed into one.
        if (item.hasDeclarationStep)
          _MarkTile(
            key: const Key('tax.detail.declared'),
            label: l.taxDetailMarkDeclared,
            dueLabel: l.taxItemDeclarationDue,
            dueDate: item.declarationDueDate,
            markedAt: item.declaredAt,
            onChanged: (bool value) => cubit.setDeclared(declared: value),
          )
        else
          _AbsentStepTile(label: l.taxItemNoDeclaration),
        if (item.hasPaymentStep)
          _MarkTile(
            key: const Key('tax.detail.paid'),
            label: l.taxDetailMarkPaid,
            dueLabel: l.taxItemPaymentDue,
            dueDate: item.paymentDueDate,
            markedAt: item.paidAt,
            onChanged: (bool value) => cubit.setPaid(paid: value),
          )
        else
          _AbsentStepTile(label: l.taxItemNoPayment),

        if (item.isConditional) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l.taxItemConditional,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        const Divider(height: 32),
        _AmountSection(item: item),
        const Divider(height: 32),
        _NoteSection(item: item),
        const Divider(height: 32),

        // Dismissal is an action, not a delete. The row survives — it is the
        // sharpest signal we get that the generated calendar is wrong for
        // this taxpayer, and a deleted row would be regenerated anyway.
        TextButton.icon(
          key: const Key('tax.detail.dismiss'),
          onPressed: () =>
              cubit.setDismissed(dismissed: item.dismissedAt == null),
          icon: Icon(
            item.dismissedAt == null ? Icons.block : Icons.undo,
          ),
          label: Text(
            item.dismissedAt == null
                ? l.taxDetailDismiss
                : l.taxDetailUndismiss,
          ),
        ),
      ],
    );
  }
}

/// A deadline plus the switch that marks it done.
class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.label,
    required this.dueLabel,
    required this.dueDate,
    required this.markedAt,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String dueLabel;
  final DateTime? dueDate;
  final DateTime? markedAt;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateTime? due = dueDate;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        due == null
            ? '$dueLabel: ${l.taxItemDateMissing}'
            : '$dueLabel: ${DateFormat.yMMMd(locale).format(due)}',
      ),
      value: markedAt != null,
      onChanged: onChanged,
    );
  }
}

/// Says out loud that a step does not exist, rather than leaving a gap.
class _AbsentStepTile extends StatelessWidget {
  const _AbsentStepTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.remove,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The amount and, inseparably, who said it.
class _AmountSection extends StatefulWidget {
  const _AmountSection({required this.item});

  final TaxCalendarItem item;

  @override
  State<_AmountSection> createState() => _AmountSectionState();
}

class _AmountSectionState extends State<_AmountSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.item.amountMinor == null
        ? ''
        : (widget.item.amountMinor! / 100).toStringAsFixed(2),
  );
  late TaxAmountSource _source = widget.item.amountSource ==
          TaxAmountSource.unknown
      ? TaxAmountSource.accountant
      : widget.item.amountSource;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TaxObligationDetailCubit cubit =
        context.read<TaxObligationDetailCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l.taxDetailAmount, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          l.taxDetailAmountDisclaimer,
          key: const Key('tax.detail.amountDisclaimer'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('tax.detail.amountField'),
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: l.taxDetailAmountHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(l.taxDetailAmountSource, style: theme.textTheme.bodySmall),
        // Only the two human sources. The enum has no third value, so this
        // list cannot grow one by accident.
        SegmentedButton<TaxAmountSource>(
          key: const Key('tax.detail.amountSource'),
          segments: <ButtonSegment<TaxAmountSource>>[
            ButtonSegment<TaxAmountSource>(
              value: TaxAmountSource.accountant,
              label: Text(taxAmountSourceLabel(l, TaxAmountSource.accountant)),
            ),
            ButtonSegment<TaxAmountSource>(
              value: TaxAmountSource.user,
              label: Text(taxAmountSourceLabel(l, TaxAmountSource.user)),
            ),
          ],
          selected: <TaxAmountSource>{_source},
          showSelectedIcon: false,
          onSelectionChanged: (Set<TaxAmountSource> picked) =>
              setState(() => _source = picked.first),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const Key('tax.detail.saveAmount'),
            onPressed: () => cubit.setAmount(
              amountMinor: _parseMinor(_controller.text),
              source: _source,
            ),
            child: Text(l.taxCustomSave),
          ),
        ),
        if (widget.item.amountMinor != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '${formatMinor(
              widget.item.amountMinor!,
              'TRY',
              locale: Localizations.localeOf(context).toLanguageTag(),
            )} · ${taxAmountSourceLabel(l, widget.item.amountSource)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Parses the typed amount into minor units.
  ///
  /// Accepts both decimal separators — a Turkish keyboard produces a comma —
  /// and returns null for anything it cannot read, which clears the amount
  /// rather than storing a number nobody meant.
  static int? _parseMinor(String raw) {
    final String cleaned = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (cleaned.isEmpty) {
      return null;
    }
    final double? value = double.tryParse(cleaned);
    if (value == null || value < 0) {
      return null;
    }
    return (value * 100).round();
  }
}

/// The user's own note.
class _NoteSection extends StatefulWidget {
  const _NoteSection({required this.item});

  final TaxCalendarItem item;

  @override
  State<_NoteSection> createState() => _NoteSectionState();
}

class _NoteSectionState extends State<_NoteSection> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.item.note ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TaxObligationDetailCubit cubit =
        context.read<TaxObligationDetailCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l.taxDetailNote, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const Key('tax.detail.noteField'),
          controller: _controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: l.taxDetailNoteHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const Key('tax.detail.saveNote'),
            onPressed: () => cubit.setNote(_controller.text),
            child: Text(l.taxCustomSave),
          ),
        ),
      ],
    );
  }
}
