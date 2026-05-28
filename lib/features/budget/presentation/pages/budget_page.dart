import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/features/budget/domain/entities/budget_snapshot.dart';
import 'package:smartspend/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_category_tile.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_create_sheet.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_empty_state.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_general_card.dart';
import 'package:smartspend/features/budget/presentation/widgets/budget_permission_banner.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Budget tab entry point — wires the page-scoped [BudgetBloc] and
/// dispatches the boot event so both Drift watch streams open
/// immediately.
class BudgetPage extends StatelessWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BudgetBloc>(
      create: (_) => sl<BudgetBloc>()..add(const BudgetSubscribed()),
      child: const _BudgetView(),
    );
  }
}

class _BudgetView extends StatelessWidget {
  const _BudgetView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.budgetTitle)),
      body: BlocConsumer<BudgetBloc, BudgetState>(
        listenWhen: (BudgetState prev, BudgetState curr) {
          // Only react when a *fresh* transient failure lands. Without
          // this guard the SnackBar would re-fire on every emission while
          // the same failure is still attached.
          if (curr is! BudgetLoaded) return false;
          if (prev is! BudgetLoaded) return curr.transientFailure != null;
          return prev.transientFailure != curr.transientFailure &&
              curr.transientFailure != null;
        },
        listener: (BuildContext ctx, BudgetState state) {
          if (state is! BudgetLoaded) return;
          final f = state.transientFailure;
          if (f == null) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text(l.budgetWriteFailed(f.message))),
          );
        },
        builder: (BuildContext ctx, BudgetState state) {
          return switch (state) {
            BudgetInitial() ||
            BudgetLoading() =>
              const Center(child: CircularProgressIndicator()),
            BudgetError(:final failure) => _ErrorView(message: failure.message),
            BudgetLoaded() => _LoadedView(state: state),
          };
        },
      ),
      floatingActionButton: BlocBuilder<BudgetBloc, BudgetState>(
        builder: (BuildContext ctx, BudgetState state) {
          if (state is! BudgetLoaded || state.isEmpty) {
            // Empty state already exposes a CTA — avoid duplicate
            // affordance.
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: () => _openCreate(ctx),
            icon: const Icon(Icons.add_rounded),
            label: Text(l.budgetCreateFab),
          );
        },
      ),
    );
  }

  Future<void> _openCreate(BuildContext context) async {
    final BudgetBloc bloc = context.read<BudgetBloc>();
    final BudgetSheetResult? r = await BudgetCreateSheet.show(context);
    if (r == null) return;
    bloc.add(
      BudgetCreated(
        amountMinor: r.amountMinor,
        period: r.period,
        startDate: r.startDate,
        categoryId: r.categoryId,
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});

  final BudgetLoaded state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final BudgetSnapshot? general = state.general;
    final List<BudgetSnapshot> categories = state.perCategory;

    return CustomScrollView(
      slivers: <Widget>[
        if (!state.notificationsEnabled)
          SliverToBoxAdapter(
            child: BudgetPermissionBanner(
              onRequest: () => context
                  .read<BudgetBloc>()
                  .add(const BudgetPermissionRequested()),
            ),
          ),
        if (state.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: BudgetEmptyState(
              onCreate: () => _openCreate(context, editing: null),
            ),
          )
        else ...<Widget>[
          if (general != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: BudgetGeneralCard(
                  snapshot: general,
                  onTap: () => _openCreate(context, editing: general),
                ),
              ),
            ),
          if (categories.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  l.budgetCategoriesSection,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          SliverList.builder(
            itemCount: categories.length,
            itemBuilder: (BuildContext ctx, int index) {
              final BudgetSnapshot s = categories[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: BudgetCategoryTile(
                  snapshot: s,
                  onTap: () => _openCreate(context, editing: s),
                  onDelete: () => context
                      .read<BudgetBloc>()
                      .add(BudgetDeleted(id: s.budget.id)),
                ),
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ],
    );
  }

  Future<void> _openCreate(
    BuildContext context, {
    required BudgetSnapshot? editing,
  }) async {
    final BudgetBloc bloc = context.read<BudgetBloc>();
    final BudgetSheetResult? r =
        await BudgetCreateSheet.show(context, editing: editing);
    if (r == null) return;
    if (r.deleted && editing != null) {
      bloc.add(BudgetDeleted(id: editing.budget.id));
      return;
    }
    if (editing == null) {
      bloc.add(
        BudgetCreated(
          amountMinor: r.amountMinor,
          period: r.period,
          startDate: r.startDate,
          categoryId: r.categoryId,
        ),
      );
    } else {
      bloc.add(
        BudgetUpdated(
          id: editing.budget.id,
          amountMinor: r.amountMinor,
          period: r.period,
          startDate: r.startDate,
        ),
      );
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            l.budgetErrorTitle,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () =>
                context.read<BudgetBloc>().add(const BudgetSubscribed()),
            child: Text(l.budgetErrorRetry),
          ),
        ],
      ),
    );
  }
}
