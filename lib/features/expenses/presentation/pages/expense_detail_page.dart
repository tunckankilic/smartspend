import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_detail_bloc.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Detail screen for a single expense.
///
/// Sprint 3.1 ships the read-only layout + delete; Sprint 3.2 will pop a
/// shared edit form on top via the FAB.
class ExpenseDetailPage extends StatelessWidget {
  const ExpenseDetailPage({required this.expenseId, super.key});

  final int expenseId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ExpenseDetailBloc>(
      create: (_) => sl<ExpenseDetailBloc>()
        ..add(ExpenseDetailRequested(id: expenseId)),
      child: const _ExpenseDetailView(),
    );
  }
}

class _ExpenseDetailView extends StatelessWidget {
  const _ExpenseDetailView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.expenseDetailTitle),
        actions: <Widget>[
          BlocBuilder<ExpenseDetailBloc, ExpenseDetailState>(
            buildWhen: (ExpenseDetailState p, ExpenseDetailState n) => p != n,
            builder: (BuildContext context, ExpenseDetailState state) {
              if (state is! ExpenseDetailLoaded || state.expense == null) {
                return const SizedBox.shrink();
              }
              final Expense e = state.expense!;
              return IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l.expenseDetailEdit,
                onPressed: () => GoRouter.of(context)
                    .push('/expenses/${e.id}/edit', extra: e),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<ExpenseDetailBloc, ExpenseDetailState>(
        listenWhen: (ExpenseDetailState p, ExpenseDetailState n) => p != n,
        listener: (BuildContext context, ExpenseDetailState state) {
          if (state is ExpenseDetailDeleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.expenseDetailDeletedSnack)),
            );
            GoRouter.of(context).pop();
          } else if (state is ExpenseDetailError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_failureMessage(l, state.failure))),
            );
          }
        },
        builder: (BuildContext context, ExpenseDetailState state) {
          return switch (state) {
            ExpenseDetailInitial() ||
            ExpenseDetailLoading() =>
              const Center(child: CircularProgressIndicator()),
            ExpenseDetailLoaded(expense: final Expense? e) =>
              e == null ? _NotFound(l: l) : _Loaded(expense: e),
            ExpenseDetailDeleted() =>
              const Center(child: CircularProgressIndicator()),
            ExpenseDetailError(:final Failure failure) =>
              _ErrorBody(message: _failureMessage(l, failure)),
          };
        },
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final DateFormat dateFmt = DateFormat.yMMMMd(locale).add_Hm();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
      children: <Widget>[
        Center(
          child: Column(
            children: <Widget>[
              CircleAvatar(
                radius: 36,
                backgroundColor:
                    Color(expense.category.color).withValues(alpha: 0.18),
                foregroundColor: Color(expense.category.color),
                child: Icon(
                  iconForCategory(expense.category.icon),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                formatMinor(
                  expense.amount,
                  expense.currency,
                  locale: locale,
                ),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                expense.category.name,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                dateFmt.format(expense.date.toLocal()),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (expense.note != null && expense.note!.isNotEmpty)
          _DetailTile(
            icon: Icons.notes_rounded,
            label: l.expenseDetailNoteLabel,
            value: expense.note!,
          ),
        if (expense.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.label_outline_rounded,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.expenseDetailTagsLabel,
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: expense.tags
                          .map(
                            (String t) => Chip(
                              label: Text(t),
                              avatar: const Icon(
                                Icons.label_outline_rounded,
                                size: 16,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        _DetailTile(
          icon: expense.isManual
              ? Icons.edit_note_rounded
              : Icons.receipt_long_rounded,
          label: l.expenseDetailOriginLabel,
          value: expense.isManual
              ? l.expenseDetailOriginManual
              : l.expenseDetailOriginScan,
        ),
        if (expense.isRecurring && expense.recurringPeriod != null)
          _DetailTile(
            icon: Icons.autorenew_rounded,
            label: l.expenseDetailRecurringLabel,
            value: _periodLabel(l, expense.recurringPeriod!),
          ),
        if (expense.receiptId != null)
          _DetailTile(
            icon: Icons.image_outlined,
            label: l.expenseDetailReceiptLabel,
            value: l.expenseDetailReceiptImageSoon,
          ),
        if (expense.isPendingSync)
          _DetailTile(
            icon: Icons.cloud_upload_outlined,
            label: l.expenseDetailSyncLabel,
            value: l.expenseDetailSyncPending,
          ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _confirmDelete(context),
          icon: Icon(
            Icons.delete_outline_rounded,
            color: theme.colorScheme.error,
          ),
          label: Text(
            l.expenseDetailDelete,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
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

  Future<void> _confirmDelete(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(l.expenseDetailDeleteTitle),
            content: Text(l.expenseDetailDeleteBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.editCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.expenseListDeleteConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      context
          .read<ExpenseDetailBloc>()
          .add(const ExpenseDetailDeletedRequested());
    }
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: theme.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l.expenseDetailNotFound, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _failureMessage(AppLocalizations l, Failure failure) {
  return switch (failure) {
    CacheFailure() => l.expenseListErrorCache,
    NetworkFailure() => l.expenseListErrorNetwork,
    _ => l.expenseListErrorGeneric,
  };
}
