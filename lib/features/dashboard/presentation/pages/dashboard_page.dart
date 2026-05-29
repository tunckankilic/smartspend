import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/widgets/sync_indicator.dart';
import 'package:smartspend/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_bar_chart.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_empty_state.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_insight_banner.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_period_chips.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_pie_chart.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_quick_actions.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_recent_list.dart';
import 'package:smartspend/features/dashboard/presentation/widgets/dashboard_summary_card.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Sprint 5 dashboard — single scrollable surface that gathers the
/// greeting, summary card, period chips, quick actions, charts, recent
/// list, and AI insight banner.
///
/// The page owns its own [DashboardBloc] for the tab's lifetime and
/// dispatches [DashboardSubscribed] on first build. Re-opening the tab
/// re-creates the bloc (factory registration) so a stale Drift
/// subscription can never leak.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  /// Tablet breakpoint per Sprint 5 prompt — phones get one column,
  /// tablets get a 2-column grid for the chart row.
  static const double kTabletBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardBloc>(
      create: (_) => sl<DashboardBloc>()..add(const DashboardSubscribed()),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const SyncOfflineBanner(),
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(top: 4, right: 4),
                child: SyncIndicator(),
              ),
            ),
            Expanded(
              child: BlocBuilder<DashboardBloc, DashboardState>(
                builder: (BuildContext context, DashboardState state) {
                  return switch (state) {
                    DashboardInitial() ||
                    DashboardLoading() =>
                      const Center(child: CircularProgressIndicator()),
                    DashboardError(failure: final Failure f) => _ErrorView(
                        message: f.message,
                        onRetry: () => context
                            .read<DashboardBloc>()
                            .add(const DashboardRefreshed()),
                        retryLabel: l.dashboardErrorRetry,
                        title: l.dashboardErrorTitle,
                      ),
                    DashboardLoaded() => _LoadedView(state: state),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});

  final DashboardLoaded state;

  @override
  Widget build(BuildContext context) {
    final Locale locale = Localizations.localeOf(context);
    final String localeTag = locale.toLanguageTag();
    final bool isTablet =
        MediaQuery.of(context).size.width >= DashboardPage.kTabletBreakpoint;

    return RefreshIndicator.adaptive(
      onRefresh: () async => context
          .read<DashboardBloc>()
          .add(const DashboardRefreshed()),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: DashboardSummaryCard(
                snapshot: state.snapshot,
                period: state.period,
                greeting: _greeting(context),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: DashboardPeriodChips(
              selected: state.period,
              onChanged: (period) => context
                  .read<DashboardBloc>()
                  .add(DashboardPeriodChanged(period: period)),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(child: DashboardQuickActions()),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          if (state.snapshot.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: DashboardEmptyState(),
            )
          else
            ..._buildContentSlivers(
              context,
              isTablet: isTablet,
              localeTag: localeTag,
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _buildContentSlivers(
    BuildContext context, {
    required bool isTablet,
    required String localeTag,
  }) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Widget barChart = _Section(
      title: l.dashboardSectionWeekly,
      child: DashboardBarChart(
        dailyTotals: state.snapshot.dailyTotals,
        currency: state.snapshot.currency,
        locale: localeTag,
      ),
    );
    final Widget pieChart = _Section(
      title: l.dashboardSectionCategories,
      child: DashboardPieChart(
        byCategory: state.snapshot.byCategoryCurrent,
        categories: state.categories,
        currency: state.snapshot.currency,
        locale: localeTag,
      ),
    );

    return <Widget>[
      if (isTablet)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: barChart),
                const SizedBox(width: 16),
                Expanded(child: pieChart),
              ],
            ),
          ),
        )
      else ...<Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(child: barChart),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(child: pieChart),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      if (state.insight != null)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: DashboardInsightBanner(
              insight: state.insight!,
              categories: state.categories,
            ),
          ),
        ),
      if (state.insight != null)
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _Section(
            title: l.dashboardSectionRecent,
            child: DashboardRecentList(
              expenses: state.snapshot.recentExpenses,
              locale: localeTag,
            ),
          ),
        ),
      ),
    ];
  }

  String _greeting(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int hour = DateTime.now().hour;
    if (hour < 5) return l.dashboardGreetingNight;
    if (hour < 12) return l.dashboardGreetingMorning;
    if (hour < 18) return l.dashboardGreetingAfternoon;
    if (hour < 22) return l.dashboardGreetingEvening;
    return l.dashboardGreetingNight;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
