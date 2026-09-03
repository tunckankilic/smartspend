import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/widgets/sync_indicator.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_calendar_cubit.dart';
import 'package:smartspend/features/taxes/presentation/widgets/tax_calendar_gaps_banner.dart';
import 'package:smartspend/features/taxes/presentation/widgets/tax_obligation_card.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Vergi takvimi — the calendar screen (1.3.0, Block 4b).
///
/// Three slices, one list, and two things that must never be silent: the
/// gaps banner, which says what could not be generated because a wizard
/// question is unanswered, and the per-card date warning. Both exist because
/// the honest state of this feature today is "incomplete", and a screen that
/// hid that would look finished and be wrong.
class TaxCalendarPage extends StatelessWidget {
  const TaxCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TaxCalendarCubit>(
      create: (BuildContext _) => sl<TaxCalendarCubit>()..subscribe(),
      child: const _TaxCalendarView(),
    );
  }
}

class _TaxCalendarView extends StatelessWidget {
  const _TaxCalendarView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.taxCalendarTitle),
        actions: const <Widget>[SyncIndicator()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('tax.calendar.addCustom'),
        onPressed: () => context.push('/taxes/custom'),
        icon: const Icon(Icons.add),
        label: Text(l.taxCalendarAddCustom),
      ),
      body: BlocConsumer<TaxCalendarCubit, TaxCalendarState>(
        // The language lives in the widget tree and the notification text is
        // built from it, so the reminder refresh is triggered here rather than
        // inside the cubit's own subscribe. The scheduler no-ops when the plan
        // has not changed, so firing on every emission is cheap.
        listener: (BuildContext context, TaxCalendarState state) {
          if (state is TaxCalendarLoaded) {
            context.read<TaxCalendarCubit>().refreshReminders(
                  languageCode: Localizations.localeOf(context).languageCode,
                );
          }
        },
        builder: (BuildContext context, TaxCalendarState state) {
          return switch (state) {
            TaxCalendarLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
            TaxCalendarError(:final Object failure) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(failure.toString()),
              ),
            ),
            TaxCalendarLoaded() => _LoadedBody(state: state),
          };
        },
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.state});

  final TaxCalendarLoaded state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);

    if (!state.hasProfile) {
      return const _EmptyProfilePrompt(key: Key('tax.calendar.noProfile'));
    }

    return Column(
      children: <Widget>[
        _RangeSelector(range: state.range),
        if (state.snapshot.gaps.isNotEmpty)
          TaxCalendarGapsBanner(gaps: state.snapshot.gaps),
        Expanded(
          child: state.visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.taxCalendarEmpty,
                      key: const Key('tax.calendar.empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  key: const Key('tax.calendar.refresh'),
                  // The one place `force` is justified: the throttle exists so
                  // the app does not pester the server on its own initiative,
                  // and a user pulling the list down is not the app's
                  // initiative. Someone who suspects the date is stale should
                  // not have to wait six hours to find out.
                  onRefresh: () => context
                      .read<TaxCalendarCubit>()
                      .refreshOverrides(force: true),
                  child: ListView.builder(
                    // Without this a short list refuses to overscroll, and the
                    // gesture the refresh hangs off never fires.
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: state.visible.length + 1,
                    itemBuilder: (BuildContext context, int index) {
                      if (index == state.visible.length) {
                        return _AsOfFooter(today: state.today);
                      }
                      final TaxCalendarItem item = state.visible[index];
                      return TaxObligationCard(
                        item: item,
                        today: state.today,
                        onTap: () => context.push('/taxes/${item.id}'),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// This month / next three months / past.
class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.range});

  final TaxCalendarRange range;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SegmentedButton<TaxCalendarRange>(
        key: const Key('tax.calendar.range'),
        segments: <ButtonSegment<TaxCalendarRange>>[
          ButtonSegment<TaxCalendarRange>(
            value: TaxCalendarRange.thisMonth,
            label: Text(l.taxCalendarRangeThisMonth),
          ),
          ButtonSegment<TaxCalendarRange>(
            value: TaxCalendarRange.upcoming,
            label: Text(l.taxCalendarRangeUpcoming),
          ),
          ButtonSegment<TaxCalendarRange>(
            value: TaxCalendarRange.past,
            label: Text(l.taxCalendarRangePast),
          ),
        ],
        selected: <TaxCalendarRange>{range},
        showSelectedIcon: false,
        onSelectionChanged: (Set<TaxCalendarRange> selection) =>
            context.read<TaxCalendarCubit>().showRange(selection.first),
      ),
    );
  }
}

/// The "as of `<date>`" line under the list.
///
/// Not decoration: every state on this screen is derived from the current
/// date rather than stored, so the list is only true as of the day it was
/// computed. Saying which day is cheap and stops a stale screen from lying.
class _AsOfFooter extends StatelessWidget {
  const _AsOfFooter({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Text(
        l.taxCalendarAsOf(DateFormat.yMMMd(locale).format(today)),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Shown before the wizard has ever been answered.
class _EmptyProfilePrompt extends StatelessWidget {
  const _EmptyProfilePrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.event_note,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l.taxCalendarNoProfileTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.taxCalendarNoProfileBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('tax.calendar.startWizard'),
              onPressed: () => context.push('/taxes/profile'),
              child: Text(l.taxCalendarNoProfileAction),
            ),
          ],
        ),
      ),
    );
  }
}
