import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_insight.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Card surfaced above the recent-expenses list when the rule engine
/// fires. Tapping it drills down into the affected category's filtered
/// expense list.
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
    final Category? cat = _findCategory(categories, insight.categoryId);
    final Color tone = insight.tone == DashboardInsightTone.warning
        ? Colors.orange.shade600
        : Colors.green.shade600;

    final String message = l.dashboardInsightSpike(
      cat?.name ?? '#${insight.categoryId}',
      insight.deltaPercent.abs().toStringAsFixed(0),
    );

    return Card(
      elevation: 0,
      color: tone.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tone.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/expenses?categoryId=${insight.categoryId}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: tone,
                child: Icon(
                  iconForCategory(cat?.icon ?? 'more_horiz'),
                  color: cs.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Category? _findCategory(List<Category> all, int id) {
    for (final Category c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}
