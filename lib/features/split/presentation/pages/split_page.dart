import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/domain/usecases/share_split_formatter.dart';
import 'package:smartspend/features/split/presentation/bloc/split_bloc.dart';
import 'package:smartspend/features/split/presentation/widgets/split_assignment_sheet.dart';
import 'package:smartspend/features/split/presentation/widgets/split_participant_chips.dart';
import 'package:smartspend/features/split/presentation/widgets/split_summary_card.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Hesap Bölüşme ekranı (Sprint 7).
///
/// Page-scoped bloc — closing the page disposes the session. Receives
/// the `receiptId` via GoRouter path param; the bloc dispatches
/// `SplitStarted` on mount.
class SplitPage extends StatelessWidget {
  const SplitPage({required this.receiptId, super.key});

  final int receiptId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SplitBloc>(
      create: (BuildContext _) =>
          sl<SplitBloc>()..add(SplitStarted(receiptId: receiptId)),
      child: const _SplitView(),
    );
  }
}

class _SplitView extends StatelessWidget {
  const _SplitView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.splitTitle)),
      body: BlocConsumer<SplitBloc, SplitState>(
        listener: (BuildContext ctx, SplitState s) {
          if (s is SplitLoaded && s.transientFailure != null) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(l.splitShareFailed)),
            );
          }
        },
        builder: (BuildContext ctx, SplitState s) {
          return switch (s) {
            SplitInitial() ||
            SplitLoading() =>
              const Center(child: CircularProgressIndicator()),
            SplitError() => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l.splitLoadFailed,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            SplitLoaded() => _LoadedBody(state: s),
          };
        },
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.state});

  final SplitLoaded state;

  Future<void> _onItemTap(BuildContext context, SplitItem item) async {
    if (state.session.participants.isEmpty) return;
    final List<String>? picked = await SplitAssignmentSheet.show(
      context,
      itemName: item.name,
      participants: state.session.participants,
      selected: state.session.assignments[item.id] ?? const <String>[],
    );
    if (picked == null) return;
    if (!context.mounted) return;
    context
        .read<SplitBloc>()
        .add(SplitItemAssigned(itemId: item.id, participantIds: picked));
  }

  Future<void> _onShare(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final String payload = ShareSplitFormatter.format(
      session: state.session,
      totalsMinor: state.perPersonMinor,
      locale: locale,
      title: l.splitShareHeading,
      headerBuilder: (String store, String date) =>
          l.splitShareHeader(date, store),
      perPersonBuilder: (String name, String amount) =>
          l.splitSharePerPerson(amount, name),
      totalBuilder: l.splitShareTotal,
    );
    context.read<SplitBloc>().add(SplitShareRequested(payload: payload));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final bool canShare = state.session.participants.isNotEmpty;
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SplitParticipantChips(
              participants: state.session.participants,
              onAdded: (String name) => context
                  .read<SplitBloc>()
                  .add(SplitParticipantAdded(name: name)),
              onRemoved: (String id) => context
                  .read<SplitBloc>()
                  .add(SplitParticipantRemoved(participantId: id)),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<SplitType>(
              segments: <ButtonSegment<SplitType>>[
                ButtonSegment<SplitType>(
                  value: SplitType.equal,
                  label: Text(l.splitTypeEqual),
                  icon: const Icon(Icons.equalizer),
                ),
                ButtonSegment<SplitType>(
                  value: SplitType.custom,
                  label: Text(l.splitTypeCustom),
                  icon: const Icon(Icons.tune),
                ),
              ],
              selected: <SplitType>{state.session.splitType},
              onSelectionChanged: (Set<SplitType> sel) => context
                  .read<SplitBloc>()
                  .add(SplitTypeChanged(type: sel.first)),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l.splitItemsLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverList.builder(
          itemCount: state.session.items.length,
          itemBuilder: (BuildContext ctx, int i) {
            final SplitItem item = state.session.items[i];
            final List<String> assigned =
                state.session.assignments[item.id] ?? const <String>[];
            return ListTile(
              key: Key('split.item.${item.id}'),
              title: Text(item.name),
              subtitle: state.session.splitType == SplitType.custom
                  ? Text(_assigneeNames(assigned))
                  : null,
              trailing: Text(
                formatMinor(
                  item.totalPriceMinor,
                  state.session.currency,
                  locale: locale,
                ),
              ),
              onTap: state.session.splitType == SplitType.custom
                  ? () => _onItemTap(ctx, item)
                  : null,
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SplitSummaryCard(
              session: state.session,
              perPersonMinor: state.perPersonMinor,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const Key('split.share'),
              onPressed: canShare ? () => _onShare(context) : null,
              icon: const Icon(Icons.share),
              label: Text(l.splitShareButton),
            ),
          ),
        ),
      ],
    );
  }

  String _assigneeNames(List<String> ids) {
    if (ids.isEmpty) return '—';
    final Map<String, String> byId = <String, String>{
      for (final p in state.session.participants) p.id: p.name,
    };
    return ids.map((String id) => byId[id] ?? id).join(', ');
  }
}
