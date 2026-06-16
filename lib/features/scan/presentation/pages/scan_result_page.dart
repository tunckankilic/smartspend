import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/presentation/widgets/category_picker_sheet.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/presentation/bloc/receipt_edit_bloc.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// User-facing review + edit screen.
///
/// Top half is the captured receipt image (pinch-to-zoom); the bottom
/// half is a [DraggableScrollableSheet] with all editable fields. On
/// successful save the route is popped and navigation jumps to
/// `/expenses` via [GoRouter].
class ScanResultPage extends StatelessWidget {
  const ScanResultPage({required this.receipt, super.key});

  final ScannedReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReceiptEditBloc>(
      create: (_) => sl<ReceiptEditBloc>()
        ..add(ReceiptEditStarted(receipt: receipt)),
      child: _ScanResultView(initialImagePath: receipt.imagePath),
    );
  }
}

class _ScanResultView extends StatelessWidget {
  const _ScanResultView({required this.initialImagePath});

  final String initialImagePath;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.editTitle)),
      body: BlocConsumer<ReceiptEditBloc, ReceiptEditState>(
        listenWhen: (ReceiptEditState p, ReceiptEditState n) => p != n,
        listener: _onStateChange,
        builder: (BuildContext context, ReceiptEditState state) {
          return switch (state) {
            ReceiptEditInitial() => const Center(
                child: CircularProgressIndicator(),
              ),
            ReceiptEditReady() => _ReadyBody(
                state: state,
                imagePath: initialImagePath,
              ),
            ReceiptEditSaving() => Stack(
                children: <Widget>[
                  _ImageHero(imagePath: initialImagePath),
                  const _SavingOverlay(),
                ],
              ),
            ReceiptEditSaved() => const Center(
                child: CircularProgressIndicator(),
              ),
            ReceiptEditFailure() => const SizedBox.shrink(),
          };
        },
      ),
    );
  }

  void _onStateChange(BuildContext context, ReceiptEditState state) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (state is ReceiptEditSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.editSavedSnack)),
      );
      GoRouter.of(context).go('/expenses');
    } else if (state is ReceiptEditFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.editErrorSaveFailed)),
      );
    }
  }
}

class _ImageHero extends StatelessWidget {
  const _ImageHero({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (imagePath.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.receipt_long_rounded,
          size: 80,
          color: cs.onSurface.withValues(alpha: 0.4),
        ),
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder:
            (BuildContext c, Object e, StackTrace? s) => Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_rounded, color: cs.error),
        ),
      ),
    );
  }
}

class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              l.editSaving,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.state, required this.imagePath});

  final ReceiptEditReady state;
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // Image fills the top ~40% of the viewport behind the sheet.
        Positioned.fill(
          child: Column(
            children: <Widget>[
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.4,
                child: _ImageHero(imagePath: imagePath),
              ),
              const Spacer(),
            ],
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder:
              (BuildContext context, ScrollController controller) {
            return _EditForm(state: state, scrollController: controller);
          },
        ),
      ],
    );
  }
}

class _EditForm extends StatelessWidget {
  const _EditForm({required this.state, required this.scrollController});

  final ReceiptEditReady state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final int computed = ReceiptEditBloc.computeTotal(state.receipt.items);

    return Material(
      color: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StoreField(receipt: state.receipt),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(child: _DateField(receipt: state.receipt)),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: _CurrencyField(currency: state.receipt.currency),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DefaultCategoryField(state: state),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(l.editItemsHeader, style: theme.textTheme.titleMedium),
              TextButton.icon(
                onPressed: () => context
                    .read<ReceiptEditBloc>()
                    .add(const ReceiptItemAdded()),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.editAddItem),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List<Widget>.generate(state.receipt.items.length, (int i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ItemCard(
                index: i,
                item: state.receipt.items[i],
                categories: state.categories,
                currency: state.receipt.currency,
              ),
            );
          }),
          const SizedBox(height: 12),
          _TotalsRow(
            ocrTotal: state.receipt.total,
            computed: computed,
            currency: state.receipt.currency,
          ),
          const SizedBox(height: 16),
          if (state.validationErrors.isNotEmpty)
            _ValidationBanner(errors: state.validationErrors),
          const SizedBox(height: 16),
          _ActionButtons(),
        ],
      ),
    );
  }
}

// =============================================================================
// Fields
// =============================================================================

class _StoreField extends StatefulWidget {
  const _StoreField({required this.receipt});

  final ScannedReceipt receipt;

  @override
  State<_StoreField> createState() => _StoreFieldState();
}

class _StoreFieldState extends State<_StoreField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.receipt.storeName ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        labelText: l.editStoreLabel,
        hintText: l.editStoreHint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.store_rounded),
      ),
      onChanged: (String v) => context
          .read<ReceiptEditBloc>()
          .add(ReceiptStoreNameChanged(storeName: v)),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.receipt});

  final ScannedReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime date = receipt.date ?? DateTime.now().toUtc();
    final String locale = Localizations.localeOf(context).toString();
    final String text = DateFormat.yMMMd(locale).format(date);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: l.editDateLabel,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.calendar_today_rounded),
      ),
      child: InkWell(
        onTap: () async {
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate: date.toLocal(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked == null || !context.mounted) return;
          context
              .read<ReceiptEditBloc>()
              .add(ReceiptDateChanged(date: DateTime.utc(
                picked.year,
                picked.month,
                picked.day,
              )));
        },
        child: Text(text),
      ),
    );
  }
}

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({required this.currency});

  final String currency;

  static const List<String> _supported = <String>['TRY', 'EUR', 'GBP', 'USD'];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String value = _supported.contains(currency) ? currency : 'TRY';
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: l.editCurrencyLabel,
        border: const OutlineInputBorder(),
      ),
      items: _supported
          .map(
            (String c) => DropdownMenuItem<String>(
              value: c,
              child: Text(c),
            ),
          )
          .toList(growable: false),
      onChanged: (String? picked) {
        if (picked == null) return;
        context
            .read<ReceiptEditBloc>()
            .add(ReceiptCurrencyChanged(currency: picked));
      },
    );
  }
}

class _DefaultCategoryField extends StatelessWidget {
  const _DefaultCategoryField({required this.state});

  final ReceiptEditReady state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Category? selected = state.categories
        .where((Category c) => c.id == state.defaultCategoryId)
        .cast<Category?>()
        .firstWhere((_) => true, orElse: () => null);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final CategoryPickerResult? r = await CategoryPickerSheet.show(
          context,
          categories: state.categories,
        );
        if (r == null || !context.mounted) return;
        if (r is CategoryPickerSelected) {
          context.read<ReceiptEditBloc>().add(
            ReceiptDefaultCategoryChanged(categoryId: r.category.id),
          );
        } else if (r is CategoryPickerCreated) {
          context.read<ReceiptEditBloc>().add(
            ReceiptCategoryCreated(
              name: r.name,
              icon: r.icon,
              color: r.color,
            ),
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l.editDefaultCategoryLabel,
          helperText: l.editDefaultCategoryHint,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: <Widget>[
            if (selected != null) ...<Widget>[
              Icon(
                iconForCategory(selected.icon),
                color: Color(selected.color),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(selected.name)),
            ] else
              Expanded(
                child: Text(
                  '—',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Item card
// =============================================================================

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.index,
    required this.item,
    required this.categories,
    required this.currency,
  });

  final int index;
  final ScannedItem item;
  final List<Category> categories;
  final String currency;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
    _qtyCtrl = TextEditingController(text: widget.item.quantity.toString());
    _priceCtrl = TextEditingController(
      text: (widget.item.totalPrice / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    final num qty = num.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 1;
    final int? minor = parseMinorInput(_priceCtrl.text);
    final int total = minor ?? widget.item.totalPrice;
    final int unit = qty == 0 ? total : (total / qty).round();
    context.read<ReceiptEditBloc>().add(
      ReceiptItemUpdated(
        index: widget.index,
        item: widget.item.copyWith(
          name: _nameCtrl.text.trim(),
          quantity: qty,
          unitPrice: unit,
          totalPrice: total,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Category? category = widget.categories
        .where((Category c) => c.id == widget.item.categoryId)
        .cast<Category?>()
        .firstWhere((_) => true, orElse: () => null);

    return Dismissible(
      key: ValueKey<String>('item-${widget.index}-${widget.item.name}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => context
          .read<ReceiptEditBloc>()
          .add(ReceiptItemRemoved(index: widget.index)),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: l.editItemNameLabel),
                onChanged: (_) => _commit(),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l.editItemQuantityLabel,
                      ),
                      onChanged: (_) => _commit(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l.editItemPriceLabel,
                      ),
                      onChanged: (_) => _commit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final CategoryPickerResult? r =
                      await CategoryPickerSheet.show(
                    context,
                    categories: widget.categories,
                  );
                  if (r == null || !context.mounted) return;
                  if (r is CategoryPickerSelected) {
                    context.read<ReceiptEditBloc>().add(
                      ReceiptItemCategoryChanged(
                        index: widget.index,
                        categoryId: r.category.id,
                      ),
                    );
                  } else if (r is CategoryPickerCreated) {
                    context.read<ReceiptEditBloc>().add(
                      ReceiptCategoryCreated(
                        name: r.name,
                        icon: r.icon,
                        color: r.color,
                      ),
                    );
                  }
                },
                child: Row(
                  children: <Widget>[
                    Icon(
                      category == null
                          ? Icons.label_outline_rounded
                          : iconForCategory(category.icon),
                      color: category == null
                          ? Theme.of(context).colorScheme.outline
                          : Color(category.color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        category?.name ?? l.editItemCategoryLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Footer
// =============================================================================

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.ocrTotal,
    required this.computed,
    required this.currency,
  });

  final int ocrTotal;
  final int computed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool mismatch = ocrTotal > 0 && (ocrTotal - computed).abs() > 50;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(l.editComputedTotal, style: theme.textTheme.titleMedium),
            Text(
              formatMinor(computed, currency),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (mismatch) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.editTotalMismatch(
                      formatMinor(ocrTotal, currency),
                      formatMinor(computed, currency),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner({required this.errors});

  final Set<ReceiptEditValidationError> errors;

  String _message(AppLocalizations l, ReceiptEditValidationError e) {
    return switch (e) {
      ReceiptEditValidationError.emptyItems => l.editErrorEmptyItems,
      ReceiptEditValidationError.nonPositiveTotal =>
        l.editErrorNonPositiveTotal,
      ReceiptEditValidationError.futureDate => l.editErrorFutureDate,
      ReceiptEditValidationError.missingDefaultCategory =>
        l.editErrorMissingDefaultCategory,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: errors
            .map(
              (ReceiptEditValidationError e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.onErrorContainer,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _message(l, e),
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        FilledButton.icon(
          onPressed: () => context
              .read<ReceiptEditBloc>()
              .add(const ReceiptEditSubmitted()),
          icon: const Icon(Icons.check_rounded),
          label: Text(l.editSave),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => GoRouter.of(context).go('/scan'),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l.editRetake),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        TextButton(
          onPressed: () => GoRouter.of(context).go('/'),
          child: Text(l.editCancel),
        ),
      ],
    );
  }
}
