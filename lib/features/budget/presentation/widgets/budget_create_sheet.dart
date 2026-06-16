import 'package:flutter/material.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/categories/presentation/widgets/category_picker_sheet.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Outbound payload for [BudgetCreateSheet]. The page maps this into
/// `BudgetCreated` / `BudgetUpdated` events on the bloc.
class BudgetSheetResult {
  const BudgetSheetResult({
    required this.amountMinor,
    required this.period,
    required this.startDate,
    required this.deleted,
    this.categoryId,
  });

  final int amountMinor;
  final BudgetPeriod period;
  final DateTime startDate;
  final int? categoryId;
  final bool deleted;
}

/// Create / edit bottom sheet for a single [BudgetSnapshot].
///
/// When [editing] is `null` the sheet behaves as "create" — the page
/// passes it through [BudgetCreated]. When non-null the sheet pre-fills
/// every field and adds a delete affordance.
class BudgetCreateSheet extends StatefulWidget {
  const BudgetCreateSheet({
    this.editing,
    super.key,
  });

  final BudgetSnapshot? editing;

  static Future<BudgetSheetResult?> show(
    BuildContext context, {
    BudgetSnapshot? editing,
  }) {
    return showModalBottomSheet<BudgetSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => BudgetCreateSheet(editing: editing),
    );
  }

  @override
  State<BudgetCreateSheet> createState() => _BudgetCreateSheetState();
}

class _BudgetCreateSheetState extends State<BudgetCreateSheet> {
  late final TextEditingController _amountCtrl;
  late BudgetPeriod _period;
  late int? _categoryId;
  late DateTime _startDate;
  String? _validationKey;
  Category? _categorySnapshot;

  @override
  void initState() {
    super.initState();
    final BudgetSnapshot? e = widget.editing;
    _amountCtrl = TextEditingController(
      text: e == null ? '' : (e.budget.amountMinor / 100).toStringAsFixed(2),
    );
    _period = e?.budget.period ?? BudgetPeriod.monthly;
    _categoryId = e?.budget.categoryId;
    _categorySnapshot = e?.category;
    _startDate = e?.budget.startDate ?? DateTime.now().toUtc();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.editing != null;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _isEditing ? l.budgetSheetTitleEdit : l.budgetSheetTitleCreate,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: !_isEditing,
              decoration: InputDecoration(
                labelText: l.budgetSheetAmountLabel,
                hintText: l.budgetSheetAmountHint,
                prefixIcon: const Icon(Icons.attach_money_rounded),
                errorText: _validationKey == 'amount'
                    ? l.budgetAmountInvalid
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l.budgetSheetPeriodLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final BudgetPeriod p in BudgetPeriod.values)
                  ChoiceChip(
                    label: Text(_periodLabel(l, p)),
                    selected: _period == p,
                    onSelected: (bool _) => setState(() => _period = p),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              l.budgetSheetCategoryLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            _categoryPickerRow(context, l),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: Text(l.budgetSheetSubmit),
            ),
            if (_isEditing) ...<Widget>[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _confirmDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                label: Text(
                  l.budgetSheetDelete,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryPickerRow(BuildContext context, AppLocalizations l) {
    final bool isGeneral = _categoryId == null;
    return Row(
      children: <Widget>[
        ChoiceChip(
          label: Text(l.budgetSheetCategoryGeneral),
          selected: isGeneral,
          onSelected: (bool _) {
            setState(() {
              _categoryId = null;
              _categorySnapshot = null;
            });
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: Icon(
              _categorySnapshot == null
                  ? Icons.category_outlined
                  : iconForCategory(_categorySnapshot!.icon),
              color: _categorySnapshot == null
                  ? null
                  : Color(_categorySnapshot!.color),
            ),
            label: Text(
              _categorySnapshot?.name ?? l.budgetSheetCategoryPick,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _openCategoryPicker,
          ),
        ),
      ],
    );
  }

  Future<void> _openCategoryPicker() async {
    final List<Category> cats = await _loadCategories();
    if (!mounted) return;
    final CategoryPickerResult? result = await CategoryPickerSheet.show(
      context,
      categories: cats,
      allowCreate: false,
    );
    if (!mounted || result == null) return;
    if (result is CategoryPickerSelected) {
      setState(() {
        _categoryId = result.category.id;
        _categorySnapshot = result.category;
      });
    }
  }

  Future<List<Category>> _loadCategories() async {
    final result = await sl<ListCategoriesUseCase>()(
      const ListCategoriesParams(),
    );
    return result.getOrElse(() => const <Category>[]);
  }

  void _submit() {
    final int? minor = parseMinorInput(_amountCtrl.text);
    if (minor == null || minor <= 0) {
      setState(() => _validationKey = 'amount');
      return;
    }
    Navigator.of(context).pop(
      BudgetSheetResult(
        amountMinor: minor,
        period: _period,
        startDate: _startDate,
        categoryId: _categoryId,
        deleted: false,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.budgetDeleteConfirmTitle),
        content: Text(l.budgetDeleteConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.budgetDeleteCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.budgetDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(
      BudgetSheetResult(
        amountMinor: widget.editing!.budget.amountMinor,
        period: widget.editing!.budget.period,
        startDate: widget.editing!.budget.startDate,
        categoryId: widget.editing!.budget.categoryId,
        deleted: true,
      ),
    );
  }

  String _periodLabel(AppLocalizations l, BudgetPeriod p) {
    return switch (p) {
      BudgetPeriod.weekly => l.budgetPeriodWeekly,
      BudgetPeriod.monthly => l.budgetPeriodMonthly,
      BudgetPeriod.yearly => l.budgetPeriodYearly,
    };
  }
}
