import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/core/utils/category_display_name.dart';
import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/core/widgets/category_icon.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Pie chart of `byCategory` totals — animated, with a center total and
/// a wrap-flow legend that doubles as drill-down buttons.
class DashboardPieChart extends StatelessWidget {
  const DashboardPieChart({
    required this.byCategory,
    required this.categories,
    required this.currency,
    required this.locale,
    super.key,
  });

  final Map<int, int> byCategory;
  final List<Category> categories;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    if (byCategory.isEmpty) {
      return const SizedBox.shrink();
    }
    final int total = byCategory.values.fold<int>(0, (int a, int b) => a + b);

    final List<MapEntry<int, int>> sorted = byCategory.entries.toList()
      ..sort(
        (MapEntry<int, int> a, MapEntry<int, int> b) =>
            b.value.compareTo(a.value),
      );

    return Column(
      children: <Widget>[
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 56,
                  startDegreeOffset: -90,
                  sections: <PieChartSectionData>[
                    for (final MapEntry<int, int> e in sorted)
                      _buildSection(context, e, total),
                  ],
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent ev, PieTouchResponse? r) {
                      if (ev is FlTapUpEvent && r?.touchedSection != null) {
                        final int idx = r!.touchedSection!.touchedSectionIndex;
                        if (idx >= 0 && idx < sorted.length) {
                          context.go(
                            '/expenses?categoryId=${sorted[idx].key}',
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    formatMinor(total, currency, locale: locale),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Legend(
          sorted: sorted,
          categories: categories,
          total: total,
          currency: currency,
          locale: locale,
        ),
      ],
    );
  }

  PieChartSectionData _buildSection(
    BuildContext context,
    MapEntry<int, int> entry,
    int total,
  ) {
    final Category? cat = _categoryFor(entry.key);
    final Color color = cat != null
        ? Color(cat.color)
        : Theme.of(context).colorScheme.primary;
    final double percent = total == 0 ? 0 : (entry.value / total) * 100;
    return PieChartSectionData(
      value: entry.value.toDouble(),
      color: color,
      radius: 36,
      title: percent >= 8 ? '${percent.toStringAsFixed(0)}%' : '',
      titleStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }

  Category? _categoryFor(int id) {
    for (final Category c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.sorted,
    required this.categories,
    required this.total,
    required this.currency,
    required this.locale,
  });

  final List<MapEntry<int, int>> sorted;
  final List<Category> categories;
  final int total;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final MapEntry<int, int> e in sorted)
          _LegendChip(
            category: _categoryFor(e.key),
            categoryId: e.key,
            amountMinor: e.value,
            percent: total == 0 ? 0 : (e.value / total) * 100,
            currency: currency,
            locale: locale,
          ),
      ],
    );
  }

  Category? _categoryFor(int id) {
    for (final Category c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.category,
    required this.categoryId,
    required this.amountMinor,
    required this.percent,
    required this.currency,
    required this.locale,
  });

  final Category? category;
  final int categoryId;
  final int amountMinor;
  final double percent;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Color color = category != null
        ? Color(category!.color)
        : Theme.of(context).colorScheme.primary;
    final String name = category == null
        ? '#$categoryId'
        : localizedCategoryName(l, category!);
    return ActionChip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 10,
        child: Icon(
          iconForCategory(category?.icon ?? 'more_horiz'),
          color: Colors.white,
          size: 12,
        ),
      ),
      label: Text(
        '$name · '
        '${formatMinor(amountMinor, currency, locale: locale)} · '
        '${percent.toStringAsFixed(0)}%',
        style: Theme.of(context).textTheme.labelSmall,
      ),
      onPressed: () => context.go('/expenses?categoryId=$categoryId'),
    );
  }
}
