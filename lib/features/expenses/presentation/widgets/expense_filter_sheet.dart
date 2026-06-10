import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Modal bottom sheet for the date / category / amount filters.
///
/// Pops a fresh [ExpenseFilter] when the user taps "Apply"; pops `null`
/// when they cancel. The list page applies the result via
/// `FilterChanged`.
class ExpenseFilterSheet extends StatefulWidget {
  const ExpenseFilterSheet({
    required this.initial,
    required this.categories,
    super.key,
  });

  final ExpenseFilter initial;
  final List<Category> categories;

  static Future<ExpenseFilter?> show(
    BuildContext context, {
    required ExpenseFilter initial,
    required List<Category> categories,
  }) {
    return showModalBottomSheet<ExpenseFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => ExpenseFilterSheet(
        initial: initial,
        categories: categories,
      ),
    );
  }

  @override
  State<ExpenseFilterSheet> createState() => _ExpenseFilterSheetState();
}

class _ExpenseFilterSheetState extends State<ExpenseFilterSheet> {
  late DateTime? _from;
  late DateTime? _to;
  late Set<int> _categoryIds;
  late int? _minAmount;
  late int? _maxAmount;
  late ExpenseSortOrder _sort;

  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;

  @override
  void initState() {
    super.initState();
    _from = widget.initial.dateFrom;
    _to = widget.initial.dateTo;
    _categoryIds = <int>{...widget.initial.categoryIds};
    _minAmount = widget.initial.minAmount;
    _maxAmount = widget.initial.maxAmount;
    _sort = widget.initial.sortOrder;
    _minCtrl = TextEditingController(
      text: _minAmount == null ? '' : (_minAmount! / 100).toStringAsFixed(2),
    );
    _maxCtrl = TextEditingController(
      text: _maxAmount == null ? '' : (_maxAmount! / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final DateFormat dateFmt = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.expenseListFilterTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),

            // Date range -----------------------------------------------
            Text(
              l.expenseListFilterDateRange,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _from ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _from = picked.toUtc());
                      }
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      _from == null
                          ? l.expenseListFilterDateFrom
                          : dateFmt.format(_from!.toLocal()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _to ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _to = picked.toUtc());
                      }
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      _to == null
                          ? l.expenseListFilterDateTo
                          : dateFmt.format(_to!.toLocal()),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Text(
              l.expenseListFilterCategories,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.categories
                  .map(
                    (Category c) => FilterChip(
                      avatar: Icon(
                        iconForCategory(c.icon),
                        size: 16,
                        color: Color(c.color),
                      ),
                      label: Text(c.name),
                      selected: _categoryIds.contains(c.id),
                      onSelected: (bool sel) {
                        setState(() {
                          if (sel) {
                            _categoryIds.add(c.id);
                          } else {
                            _categoryIds.remove(c.id);
                          }
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),

            const SizedBox(height: 16),
            Text(l.expenseListFilterAmount, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _minCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l.expenseListFilterMin,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (String v) => _minAmount = parseMinorInput(v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l.expenseListFilterMax,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (String v) => _maxAmount = parseMinorInput(v),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Text(l.expenseListSortTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ExpenseSortOrder.values
                  .map((ExpenseSortOrder o) {
                    return ChoiceChip(
                      label: Text(_sortLabel(l, o)),
                      selected: _sort == o,
                      onSelected: (_) => setState(() => _sort = o),
                    );
                  })
                  .toList(growable: false),
            ),

            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(ExpenseFilter.empty);
                    },
                    child: Text(l.expenseListFilterClear),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        ExpenseFilter(
                          dateFrom: _from,
                          dateTo: _to,
                          categoryIds: _categoryIds,
                          minAmount: _minAmount,
                          maxAmount: _maxAmount,
                          searchQuery: widget.initial.searchQuery,
                          sortOrder: _sort,
                        ),
                      );
                    },
                    child: Text(l.expenseListFilterApply),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(AppLocalizations l, ExpenseSortOrder o) {
    switch (o) {
      case ExpenseSortOrder.dateDesc:
        return l.expenseListSortDateDesc;
      case ExpenseSortOrder.dateAsc:
        return l.expenseListSortDateAsc;
      case ExpenseSortOrder.amountDesc:
        return l.expenseListSortAmountDesc;
      case ExpenseSortOrder.amountAsc:
        return l.expenseListSortAmountAsc;
    }
  }
}
