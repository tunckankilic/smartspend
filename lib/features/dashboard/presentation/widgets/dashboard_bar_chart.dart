import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Bar chart of daily totals over the selected period.
///
/// Renders one bar per day from [dailyTotals] (sorted ascending). Today's
/// bar is highlighted in the primary color. Y axis labels show compact
/// currency formatting; bars convert minor units to major before render.
class DashboardBarChart extends StatelessWidget {
  const DashboardBarChart({
    required this.dailyTotals,
    required this.currency,
    required this.locale,
    super.key,
  });

  final Map<DateTime, int> dailyTotals;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    final List<MapEntry<DateTime, int>> entries = dailyTotals.entries.toList()
      ..sort((MapEntry<DateTime, int> a, MapEntry<DateTime, int> b) =>
          a.key.compareTo(b.key));

    if (entries.isEmpty) {
      return const SizedBox(height: 180);
    }

    final DateTime today = DateTime.utc(
      DateTime.now().toUtc().year,
      DateTime.now().toUtc().month,
      DateTime.now().toUtc().day,
    );
    final int maxMinor = entries
        .map((MapEntry<DateTime, int> e) => e.value)
        .fold<int>(0, (int a, int b) => a > b ? a : b);
    final double maxY = (maxMinor / 100.0).clamp(1, double.infinity);

    final List<BarChartGroupData> groups = <BarChartGroupData>[];
    for (int i = 0; i < entries.length; i++) {
      final MapEntry<DateTime, int> e = entries[i];
      final bool isToday = e.key == today;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: <BarChartRodData>[
            BarChartRodData(
              toY: e.value / 100.0,
              width: _barWidth(entries.length),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
              color: isToday ? cs.primary : cs.primary.withValues(alpha: 0.45),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: BarChart(
          BarChartData(
            maxY: maxY * 1.15,
            barGroups: groups,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    if (value == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        _yLabel(value, currency, locale),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final int i = value.toInt();
                    if (i < 0 || i >= entries.length) {
                      return const SizedBox.shrink();
                    }
                    // Only show every Nth label to keep the axis legible.
                    final int step =
                        (entries.length / 7).ceil().clamp(1, 30);
                    if (i % step != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat.Md(locale).format(entries[i].key),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) =>
                    cs.inverseSurface.withValues(alpha: 0.95),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                getTooltipItem:
                    (BarChartGroupData group, int _, BarChartRodData rod, _) {
                  final int i = group.x;
                  final DateTime day = entries[i].key;
                  final NumberFormat fmt = NumberFormat.currency(
                    locale: locale,
                    symbol: _symbolFor(currency),
                    decimalDigits: 2,
                  );
                  return BarTooltipItem(
                    '${DateFormat.yMMMd(locale).format(day)}\n'
                    '${fmt.format(rod.toY)}',
                    TextStyle(
                      color: cs.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _barWidth(int n) {
    if (n <= 7) return 18;
    if (n <= 31) return 8;
    return 4;
  }

  String _yLabel(double majorValue, String currency, String locale) {
    final NumberFormat fmt = NumberFormat.compactCurrency(
      locale: locale,
      symbol: _symbolFor(currency),
      decimalDigits: 0,
    );
    return fmt.format(majorValue);
  }

  String _symbolFor(String currency) {
    switch (currency) {
      case 'TRY':
        return '₺';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'USD':
        return r'$';
      default:
        return currency;
    }
  }
}
