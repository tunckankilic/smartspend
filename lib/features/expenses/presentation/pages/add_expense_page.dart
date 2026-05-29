import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/presentation/widgets/category_picker_sheet.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/presentation/bloc/add_expense_bloc.dart';
import 'package:smartspend/features/expenses/presentation/widgets/tag_input.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Manual expense form. Used for both **adding** a new row and
/// **editing** an existing one — pass [expense] to switch into edit
/// mode.
class AddExpensePage extends StatelessWidget {
  const AddExpensePage({this.expense, super.key});

  /// `null` for add-mode; supply the source row for edit-mode.
  final Expense? expense;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AddExpenseBloc>(
      create: (_) {
        final AddExpenseBloc b = sl<AddExpenseBloc>();
        if (expense == null) {
          b.add(const AddExpenseStarted());
        } else {
          b.add(AddExpenseEditStarted(expense: expense!));
        }
        return b;
      },
      child: const _AddExpenseView(),
    );
  }
}

class _AddExpenseView extends StatelessWidget {
  const _AddExpenseView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return BlocConsumer<AddExpenseBloc, AddExpenseState>(
      listenWhen: (AddExpenseState p, AddExpenseState n) => p != n,
      listener: (BuildContext context, AddExpenseState state) {
        if (state is AddExpenseSaved) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.addExpenseSavedSnack)),
          );
          GoRouter.of(context).pop();
        } else if (state is AddExpenseFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.addExpenseSaveFailed)),
          );
        }
      },
      builder: (BuildContext context, AddExpenseState state) {
        final bool isEdit = state is AddExpenseReady &&
            state.mode == AddExpenseMode.edit;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              isEdit ? l.addExpenseTitleEdit : l.addExpenseTitleNew,
            ),
            actions: <Widget>[
              if (state is AddExpenseReady && !state.isSubmitting)
                IconButton(
                  tooltip: l.a11ySaveExpense,
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () => context
                      .read<AddExpenseBloc>()
                      .add(const AddExpenseSubmitted()),
                ),
              if (state is AddExpenseReady && state.isSubmitting)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          body: switch (state) {
            AddExpenseInitial() ||
            AddExpenseLoading() =>
              const Center(child: CircularProgressIndicator()),
            AddExpenseSaved() =>
              const Center(child: CircularProgressIndicator()),
            AddExpenseFailure() ||
            AddExpenseReady() =>
              _Form(state: state),
          },
        );
      },
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.state});

  final AddExpenseState state;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    final AddExpenseReady? ready = _readyOf(widget.state);
    _amountCtrl = TextEditingController(text: ready?.amountInput ?? '');
    _noteCtrl = TextEditingController(text: ready?.note ?? '');
  }

  AddExpenseReady? _readyOf(AddExpenseState s) =>
      s is AddExpenseReady ? s : null;

  @override
  void didUpdateWidget(covariant _Form oldWidget) {
    super.didUpdateWidget(oldWidget);
    final AddExpenseReady? ready = _readyOf(widget.state);
    if (ready == null) return;
    // Sync controller text only when bloc state diverges (e.g. when the
    // edit-mode prefill arrives). Avoid clobbering the user's caret on
    // every keystroke.
    if (_amountCtrl.text != ready.amountInput) {
      _amountCtrl.text = ready.amountInput;
    }
    final String desiredNote = ready.note ?? '';
    if (_noteCtrl.text != desiredNote) {
      _noteCtrl.text = desiredNote;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AddExpenseReady? ready = _readyOf(widget.state);
    if (ready == null) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final AddExpenseBloc bloc = context.read<AddExpenseBloc>();
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateFormat dateFmt = DateFormat.yMMMMd(locale);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        // Amount ----------------------------------------------------------
        Center(
          child: TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
            ],
            textAlign: TextAlign.center,
            autofocus: ready.mode == AddExpenseMode.add,
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: '0,00',
              border: InputBorder.none,
              errorText: ready.validationErrors
                      .contains(AddExpenseValidationError.invalidAmount)
                  ? l.addExpenseErrorAmount
                  : null,
            ),
            onChanged: (String v) =>
                bloc.add(AddExpenseAmountChanged(input: v)),
          ),
        ),
        if (ready.amountMinor != null)
          Center(
            child: Text(
              formatMinor(
                ready.amountMinor!,
                _currencyHint(ready),
                locale: locale,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        const SizedBox(height: 24),

        // Category --------------------------------------------------------
        Text(l.addExpenseCategoryLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _pickCategory(context, ready),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ready.validationErrors
                        .contains(AddExpenseValidationError.missingCategory)
                    ? theme.colorScheme.error
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: <Widget>[
                if (ready.category != null) ...<Widget>[
                  Icon(
                    iconForCategory(ready.category!.icon),
                    color: Color(ready.category!.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(ready.category!.name)),
                ] else
                  Expanded(child: Text(l.addExpenseCategoryHint)),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        if (ready.validationErrors
            .contains(AddExpenseValidationError.missingCategory))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.addExpenseErrorCategory,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),

        const SizedBox(height: 16),

        // Date ------------------------------------------------------------
        Text(l.addExpenseDateLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: ready.date.toLocal(),
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
            );
            if (picked != null && context.mounted) {
              bloc.add(AddExpenseDateSelected(date: picked));
            }
          },
          icon: const Icon(Icons.calendar_today_rounded),
          label: Text(dateFmt.format(ready.date.toLocal())),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: Alignment.centerLeft,
          ),
        ),
        if (ready.validationErrors
            .contains(AddExpenseValidationError.futureDate))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.addExpenseErrorFutureDate,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),

        const SizedBox(height: 16),

        // Note ------------------------------------------------------------
        TextField(
          controller: _noteCtrl,
          decoration: InputDecoration(
            labelText: l.addExpenseNoteLabel,
            hintText: l.addExpenseNoteHint,
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
          onChanged: (String v) =>
              bloc.add(AddExpenseNoteChanged(note: v)),
        ),

        const SizedBox(height: 16),

        // Tags ------------------------------------------------------------
        Text(l.addExpenseTagsLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TagInput(
          tags: ready.tags,
          suggestions: _mergeTagSuggestions(
            ready.suggestedTags,
            ready.availableTags,
          ),
          onAdd: (String t) => bloc.add(AddExpenseTagAdded(tag: t)),
          onRemove: (String t) =>
              bloc.add(AddExpenseTagRemoved(tag: t)),
        ),

        const SizedBox(height: 16),

        // Recurring -------------------------------------------------------
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.addExpenseRecurringLabel),
          subtitle: Text(l.addExpenseRecurringHint),
          value: ready.isRecurring,
          onChanged: (bool v) =>
              bloc.add(AddExpenseRecurringToggled(value: v)),
        ),
        if (ready.isRecurring) ...<Widget>[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: RecurringPeriod.values
                .map(
                  (RecurringPeriod p) => ChoiceChip(
                    label: Text(_periodLabel(l, p)),
                    selected: ready.recurringPeriod == p,
                    onSelected: (_) =>
                        bloc.add(AddExpensePeriodChanged(period: p)),
                  ),
                )
                .toList(growable: false),
          ),
          if (ready.validationErrors
              .contains(AddExpenseValidationError.missingRecurringPeriod))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.addExpenseErrorRecurringPeriod,
                style:
                    TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),
        ],

        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: ready.isSubmitting
              ? null
              : () => bloc.add(const AddExpenseSubmitted()),
          icon: const Icon(Icons.save_rounded),
          label: Text(
            ready.mode == AddExpenseMode.edit
                ? l.addExpenseSaveChanges
                : l.addExpenseSave,
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCategory(
    BuildContext context,
    AddExpenseReady ready,
  ) async {
    final AddExpenseBloc bloc = context.read<AddExpenseBloc>();
    final CategoryPickerResult? r = await CategoryPickerSheet.show(
      context,
      categories: ready.categories,
    );
    if (r is CategoryPickerSelected) {
      bloc.add(AddExpenseCategorySelected(category: r.category));
    } else if (r is CategoryPickerCreated) {
      bloc.add(
        AddExpenseCategoryCreated(
          name: r.name,
          icon: r.icon,
          color: r.color,
        ),
      );
    }
  }

  /// Smart-tag suggestions first, then the user's historical tag names,
  /// deduped (case-insensitive). The merged list keeps the keyword-driven
  /// hints visible even when the user has a long history of free-form
  /// tags.
  List<String> _mergeTagSuggestions(
    List<String> smart,
    List<String> historical,
  ) {
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final String s in <String>[...smart, ...historical]) {
      final String key = s.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(s);
    }
    return out;
  }

  String _currencyHint(AddExpenseReady ready) {
    // Sprint 5 will wire user_settings.default_currency. For now the
    // form always shows TRY — manual entries inherit the device default.
    return 'TRY';
  }

  String _periodLabel(AppLocalizations l, RecurringPeriod p) {
    switch (p) {
      case RecurringPeriod.weekly:
        return l.expenseDetailRecurringWeekly;
      case RecurringPeriod.monthly:
        return l.expenseDetailRecurringMonthly;
      case RecurringPeriod.yearly:
        return l.expenseDetailRecurringYearly;
    }
  }
}
