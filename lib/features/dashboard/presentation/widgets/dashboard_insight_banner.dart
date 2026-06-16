import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Card surfaced above the recent-expenses list when one of the five
/// Sprint 6 rules fires. Switches on the concrete [DashboardInsight]
/// subtype so each rule gets bespoke copy + iconography + drilldown.
class DashboardInsightBanner extends StatelessWidget {
  const DashboardInsightBanner({
    required this.insight,
    required this.categories,
    super.key,
  });

  final DashboardInsight insight;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color tone = _toneColor(insight.tone);
    final _BannerContent content = _resolveContent(context, l);

    return Card(
      elevation: 0,
      color: tone.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tone.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: content.onTap == null ? null : () => content.onTap!(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: tone,
                child: Icon(content.icon, color: cs.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  content.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (content.onTap != null)
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Subtype dispatch
  // ---------------------------------------------------------------------

  _BannerContent _resolveContent(BuildContext context, AppLocalizations l) {
    return switch (insight) {
      CategorySpikeInsight(
        :final int categoryId,
        :final double deltaPercent,
      ) =>
        _categorySpike(context, l, categoryId, deltaPercent),
      BudgetWarningInsight(
        :final int? categoryId,
        :final int percentSpent,
        :final bool isExceeded,
      ) =>
        _budgetWarning(l, categoryId, percentSpent, isExceeded: isExceeded),
      BudgetAchievementInsight(:final int? categoryId) =>
        _budgetAchievement(l, categoryId),
      FrequencyInsight(
        :final String tag,
        :final int count,
        :final int totalMinor,
      ) =>
        _frequency(context, l, tag, count, totalMinor),
      DayOfWeekInsight(:final int weekday, :final double deltaPercent) =>
        _dayOfWeek(l, weekday, deltaPercent),
    };
  }

  _BannerContent _categorySpike(
    BuildContext context,
    AppLocalizations l,
    int categoryId,
    double deltaPercent,
  ) {
    final Category? cat = _findCategory(categoryId);
    return _BannerContent(
      icon: iconForCategory(cat?.icon ?? 'more_horiz'),
      message: l.dashboardInsightSpike(
        cat?.name ?? '#$categoryId',
        deltaPercent.abs().toStringAsFixed(0),
      ),
      onTap: (BuildContext ctx) =>
          ctx.go('/expenses?categoryId=$categoryId'),
    );
  }

  _BannerContent _budgetWarning(
    AppLocalizations l,
    int? categoryId,
    int percentSpent, {
    required bool isExceeded,
  }) {
    final Category? cat =
        categoryId == null ? null : _findCategory(categoryId);
    final String label = cat?.name ?? l.budgetGeneralLabel;
    return _BannerContent(
      icon: isExceeded
          ? Icons.error_outline_rounded
          : Icons.warning_amber_rounded,
      message: isExceeded
          ? l.dashboardInsightBudgetExceeded(label, percentSpent.toString())
          : l.dashboardInsightBudgetWarning(label, percentSpent.toString()),
      onTap: (BuildContext ctx) => ctx.go('/budget'),
    );
  }

  _BannerContent _budgetAchievement(AppLocalizations l, int? categoryId) {
    final Category? cat =
        categoryId == null ? null : _findCategory(categoryId);
    final String label = cat?.name ?? l.budgetGeneralLabel;
    return _BannerContent(
      icon: Icons.emoji_events_outlined,
      message: l.dashboardInsightBudgetAchievement(label),
      onTap: (BuildContext ctx) => ctx.go('/budget'),
    );
  }

  _BannerContent _frequency(
    BuildContext context,
    AppLocalizations l,
    String tag,
    int count,
    int totalMinor,
  ) {
    final String locale = Localizations.localeOf(context).toLanguageTag();
    return _BannerContent(
      icon: Icons.repeat_rounded,
      message: l.dashboardInsightFrequency(
        tag,
        count.toString(),
        formatMinor(totalMinor, 'TRY', locale: locale),
      ),
      onTap: null,
    );
  }

  _BannerContent _dayOfWeek(
    AppLocalizations l,
    int weekday,
    double deltaPercent,
  ) {
    return _BannerContent(
      icon: Icons.calendar_today_rounded,
      message: l.dashboardInsightDayOfWeek(
        _weekdayName(l, weekday),
        deltaPercent.abs().toStringAsFixed(0),
      ),
      onTap: null,
    );
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  Color _toneColor(DashboardInsightTone tone) {
    return switch (tone) {
      DashboardInsightTone.warning => Colors.orange.shade600,
      DashboardInsightTone.positive => Colors.green.shade600,
      DashboardInsightTone.info => Colors.blue.shade600,
    };
  }

  Category? _findCategory(int id) {
    for (final Category c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String _weekdayName(AppLocalizations l, int isoWeekday) {
    return switch (isoWeekday) {
      DateTime.monday => l.weekdayMonday,
      DateTime.tuesday => l.weekdayTuesday,
      DateTime.wednesday => l.weekdayWednesday,
      DateTime.thursday => l.weekdayThursday,
      DateTime.friday => l.weekdayFriday,
      DateTime.saturday => l.weekdaySaturday,
      DateTime.sunday => l.weekdaySunday,
      _ => '',
    };
  }
}

class _BannerContent {
  const _BannerContent({
    required this.icon,
    required this.message,
    required this.onTap,
  });

  final IconData icon;
  final String message;
  final void Function(BuildContext context)? onTap;
}
