import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:dartz/dartz.dart' hide State;

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/sync_indicator.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_list_bloc.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_category_chips.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_filter_sheet.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_group.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_list_item.dart';
import 'package:smartspend/features/expenses/presentation/widgets/expense_period_chips.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Expenses tab — Sprint 3.1.
///
/// Owns its own [ExpenseListBloc] for the page's lifetime and tears it
/// down when the tab pops. Manual-entry FAB (Sprint 3.2) navigates to
/// `/expenses/new`; tapping a row pushes `/expenses/:id`.
class ExpenseListPage extends StatelessWidget {
  const ExpenseListPage({super.key, this.initialCategoryId});

  /// Optional category id pre-applied to the filter on first build —
  /// supplied by the dashboard drill-down via `/expenses?categoryId=X`.
  final int? initialCategoryId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ExpenseListBloc>(
      create: (_) {
        final ExpenseListBloc bloc = sl<ExpenseListBloc>()
          ..add(const ExpensesSubscribed());
        if (initialCategoryId != null) {
          bloc.add(
            FilterChanged(
              filter: ExpenseFilter(
                categoryIds: <int>{initialCategoryId!},
              ),
            ),
          );
        }
        return bloc;
      },
      child: const _ExpenseListView(),
    );
  }
}

class _ExpenseListView extends StatefulWidget {
  const _ExpenseListView();

  @override
  State<_ExpenseListView> createState() => _ExpenseListViewState();
}

class _ExpenseListViewState extends State<_ExpenseListView> {
  bool _searching = false;
  late final TextEditingController _searchCtrl;

  /// Backs the inline category chip row. Loaded once on mount — category
  /// edits are rare enough that the filter sheet's on-demand fetch covers
  /// staleness.
  List<Category> _categories = const <Category>[];

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final Either<Failure, List<Category>> result =
        await sl<ListCategoriesUseCase>()(const ListCategoriesParams());
    if (!mounted) return;
    result.fold(
      // Chip row simply stays hidden — the filter sheet remains available.
      (Failure f) {},
      (List<Category> categories) => setState(() => _categories = categories),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: _buildAppBar(context, l),
      body: BlocConsumer<ExpenseListBloc, ExpenseListState>(
        listenWhen: (ExpenseListState p, ExpenseListState n) {
          if (p is ExpenseListLoaded && n is ExpenseListLoaded) {
            return p.transientError != n.transientError &&
                n.transientError != null;
          }
          return false;
        },
        listener: (BuildContext context, ExpenseListState state) {
          final ExpenseListLoaded loaded = state as ExpenseListLoaded;
          final Failure? err = loaded.transientError;
          if (err != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_failureMessage(l, err))),
            );
          }
        },
        builder: (BuildContext context, ExpenseListState state) {
          return switch (state) {
            ExpenseListInitial() => const _LoadingBody(),
            ExpenseListLoading() => const _LoadingBody(),
            ExpenseListLoaded(:final List<Expense> expenses) => _LoadedBody(
              state: state,
              expenses: expenses,
              categories: _categories,
            ),
            ExpenseListError(:final Failure failure) => _ErrorBody(
              message: _failureMessage(l, failure),
            ),
          };
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => GoRouter.of(context).push('/expenses/new'),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.expenseListAdd),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppLocalizations l) {
    final ExpenseListBloc bloc = context.read<ExpenseListBloc>();
    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: l.a11yBack,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() => _searching = false);
            _searchCtrl.clear();
            bloc.add(const SearchQueried(query: ''));
          },
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.expenseListSearchHint,
            border: InputBorder.none,
          ),
          onChanged: (String v) => bloc.add(SearchQueried(query: v)),
        ),
      );
    }
    return AppBar(
      title: Text(l.navExpenses),
      actions: <Widget>[
        IconButton(
          tooltip: l.a11ySearchExpenses,
          icon: const Icon(Icons.search_rounded),
          onPressed: () => setState(() => _searching = true),
        ),
        IconButton(
          tooltip: l.a11yFilterExpenses,
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => _openFilterSheet(context),
        ),
        const SyncIndicator(),
      ],
    );
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final ExpenseListBloc bloc = context.read<ExpenseListBloc>();
    final Either<Failure, List<Category>> result =
        await sl<ListCategoriesUseCase>()(const ListCategoriesParams());
    final List<Category> categories = result.getOrElse(
      () => const <Category>[],
    );
    if (!context.mounted) return;
    final ExpenseFilter? next = await ExpenseFilterSheet.show(
      context,
      initial: bloc.state.filter,
      categories: categories,
    );
    if (next != null) {
      bloc.add(FilterChanged(filter: next));
    }
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.state,
    required this.expenses,
    required this.categories,
  });

  final ExpenseListLoaded state;
  final List<Expense> expenses;

  /// Categories backing the inline chip row; empty while loading (the
  /// row is simply omitted).
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ExpenseListBloc bloc = context.read<ExpenseListBloc>();

    final Widget filterChips = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ExpensePeriodChips(
            filter: state.filter,
            onChanged: (ExpenseFilter next) =>
                bloc.add(FilterChanged(filter: next)),
          ),
          if (categories.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            ExpenseCategoryChips(
              categories: categories,
              selectedIds: state.filter.categoryIds,
              onToggled: (int id) {
                final Set<int> next = <int>{...state.filter.categoryIds};
                if (!next.remove(id)) next.add(id);
                bloc.add(
                  FilterChanged(
                    filter: state.filter.copyWith(categoryIds: next),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );

    if (expenses.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => bloc.add(const ExpensesRefreshed()),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(child: filterChips),
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(filter: state.filter),
            ),
          ],
        ),
      );
    }

    final List<ExpenseGroup> groups = groupByDate(expenses);
    final List<_RowEntry> rows = <_RowEntry>[];
    for (final ExpenseGroup g in groups) {
      rows.add(_RowEntry.header(g.key));
      for (final Expense e in g.expenses) {
        rows.add(_RowEntry.row(e));
      }
    }

    return RefreshIndicator(
      onRefresh: () async => bloc.add(const ExpensesRefreshed()),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(child: filterChips),
          SliverToBoxAdapter(
            child: _SummaryHeader(state: state),
          ),
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (BuildContext ctx, int i) {
              final _RowEntry entry = rows[i];
              if (entry.header != null) {
                return _GroupHeader(label: _groupLabel(l, entry.header!));
              }
              final Expense e = entry.expense!;
              return ExpenseListItem(
                expense: e,
                onTap: () => GoRouter.of(context).push('/expenses/${e.id}'),
                onDelete: () => bloc.add(ExpenseDeleted(id: e.id)),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  String _groupLabel(AppLocalizations l, ExpenseGroupKey k) {
    switch (k) {
      case ExpenseGroupKey.today:
        return l.expenseListGroupToday;
      case ExpenseGroupKey.yesterday:
        return l.expenseListGroupYesterday;
      case ExpenseGroupKey.thisWeek:
        return l.expenseListGroupThisWeek;
      case ExpenseGroupKey.thisMonth:
        return l.expenseListGroupThisMonth;
      case ExpenseGroupKey.earlier:
        return l.expenseListGroupEarlier;
    }
  }
}

class _RowEntry {
  const _RowEntry.header(this.header) : expense = null;
  const _RowEntry.row(this.expense) : header = null;

  final ExpenseGroupKey? header;
  final Expense? expense;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.state});

  final ExpenseListLoaded state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l.expenseListSummaryTitle,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                formatMinor(
                  state.summary.totalMinor,
                  state.summary.currency,
                  locale: locale,
                ),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.expenseListSummaryCount(state.summary.count),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final ExpenseFilter filter;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.receipt_long_rounded,
              size: 72,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              filter.isUnfiltered
                  ? l.expenseListEmptyTitle
                  : l.expenseListEmptyFilteredTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              filter.isUnfiltered
                  ? l.expenseListEmptyBody
                  : l.expenseListEmptyFilteredBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
