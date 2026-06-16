import 'package:flutter/material.dart';

import 'package:smartspend/core/utils/currency_formatter.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Gradient hero card on top of the dashboard — greeting, period label,
/// animated total counter, delta vs previous period.
class DashboardSummaryCard extends StatelessWidget {
  const DashboardSummaryCard({
    required this.snapshot,
    required this.period,
    required this.greeting,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final DashboardPeriod period;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    final Locale locale = Localizations.localeOf(context);

    final String periodLabel = _periodLabel(l, period);
    final String? deltaText = _deltaText(l, snapshot.deltaPercent);
    final bool deltaIsUp =
        (snapshot.deltaPercent ?? 0) > 0; // up = warning, down = positive

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[cs.primary, cs.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            greeting,
            style: tt.bodyMedium?.copyWith(
              color: cs.onPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            periodLabel,
            style: tt.titleMedium?.copyWith(
              color: cs.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _AnimatedTotal(
            valueMinor: snapshot.currentTotalMinor,
            currency: snapshot.currency,
            locale: locale.toLanguageTag(),
            style: tt.displaySmall?.copyWith(
              color: cs.onPrimary,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          if (deltaText != null)
            _DeltaPill(
              text: deltaText,
              up: deltaIsUp,
              onColor: cs.onPrimary,
            )
          else
            Text(
              l.dashboardSummaryDeltaNone,
              style: tt.bodySmall?.copyWith(
                color: cs.onPrimary.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }

  String _periodLabel(AppLocalizations l, DashboardPeriod p) {
    return switch (p) {
      ThisWeekPeriod() => l.dashboardSummaryThisWeekLabel,
      ThisMonthPeriod() => l.dashboardSummaryThisMonthLabel,
      Last3MonthsPeriod() => l.dashboardSummaryLast3MonthsLabel,
      CustomPeriod() => l.dashboardSummaryCustomLabel,
    };
  }

  String? _deltaText(AppLocalizations l, double? delta) {
    if (delta == null) return null;
    final String formatted = delta.abs().toStringAsFixed(0);
    if (delta >= 0) {
      return l.dashboardSummaryDeltaUp(formatted);
    }
    return l.dashboardSummaryDeltaDown(formatted);
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({
    required this.text,
    required this.up,
    required this.onColor,
  });

  final String text;
  final bool up;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (up ? Colors.red.shade400 : Colors.green.shade400)
            .withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: onColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AnimatedTotal extends StatelessWidget {
  const _AnimatedTotal({
    required this.valueMinor,
    required this.currency,
    required this.locale,
    required this.style,
  });

  final int valueMinor;
  final String currency;
  final String locale;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: valueMinor),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, int value, _) {
        // Compact format for tablet/landscape to avoid wrap. Default
        // currency format otherwise.
        final double width = MediaQuery.of(context).size.width;
        final String text = width < 360
            ? formatMinorCompact(value, currency, locale: locale)
            : formatMinor(value, currency, locale: locale);
        return Text(text, style: style);
      },
    );
  }
}
