import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_archive_bloc.dart';
import 'package:smartspend/features/receipts/presentation/widgets/receipt_archive_card.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Fiş Arşivi (Sprint 7).
///
/// Read-only browsing surface backed by a `ReceiptArchiveBloc` watching
/// Drift. Grid by default; toggle to list via the appbar action. Search
/// bar in the appbar bottom slot is debounced inside the bloc.
class ReceiptArchivePage extends StatelessWidget {
  const ReceiptArchivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReceiptArchiveBloc>(
      create: (BuildContext _) =>
          sl<ReceiptArchiveBloc>()..add(const ReceiptArchiveSubscribed()),
      child: const _ArchiveView(),
    );
  }
}

class _ArchiveView extends StatelessWidget {
  const _ArchiveView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.archiveTitle),
        actions: <Widget>[
          BlocBuilder<ReceiptArchiveBloc, ReceiptArchiveState>(
            buildWhen: (ReceiptArchiveState a, ReceiptArchiveState b) =>
                a is! ReceiptArchiveLoaded ||
                b is! ReceiptArchiveLoaded ||
                a.layout != b.layout,
            builder: (BuildContext ctx, ReceiptArchiveState s) {
              final bool isGrid = s is! ReceiptArchiveLoaded ||
                  s.layout == ReceiptArchiveLayout.grid;
              return IconButton(
                key: const Key('archive.toggle'),
                icon: Icon(isGrid ? Icons.view_list : Icons.grid_view),
                tooltip: isGrid ? l.archiveViewList : l.archiveViewGrid,
                onPressed: () => ctx
                    .read<ReceiptArchiveBloc>()
                    .add(const ReceiptArchiveViewToggled()),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('archive.search'),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l.archiveSearchHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (String v) => context
                  .read<ReceiptArchiveBloc>()
                  .add(ReceiptArchiveSearchChanged(query: v)),
            ),
          ),
        ),
      ),
      body: BlocBuilder<ReceiptArchiveBloc, ReceiptArchiveState>(
        builder: (BuildContext ctx, ReceiptArchiveState s) {
          return switch (s) {
            ReceiptArchiveInitial() ||
            ReceiptArchiveLoading() =>
              const Center(child: CircularProgressIndicator()),
            ReceiptArchiveError() => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l.archiveLoadFailed,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ReceiptArchiveLoaded() => _Body(state: s),
          };
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final ReceiptArchiveLoaded state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (state.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.filter.isEmpty ? l.archiveEmpty : l.archiveEmptyFiltered,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }
    if (state.layout == ReceiptArchiveLayout.list) {
      return ListView.separated(
        key: const Key('archive.list'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.entries.length,
        separatorBuilder: (BuildContext _, int _) => const Divider(height: 1),
        itemBuilder: (BuildContext ctx, int i) {
          final ReceiptArchiveEntry entry = state.entries[i];
          return ReceiptArchiveCard(
            entry: entry,
            compact: true,
            onTap: () => ctx.push('/receipts/${entry.id}'),
          );
        },
      );
    }
    return GridView.builder(
      key: const Key('archive.grid'),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: state.entries.length,
      itemBuilder: (BuildContext ctx, int i) {
        final ReceiptArchiveEntry entry = state.entries[i];
        return ReceiptArchiveCard(
          entry: entry,
          onTap: () => ctx.push('/receipts/${entry.id}'),
        );
      },
    );
  }
}
