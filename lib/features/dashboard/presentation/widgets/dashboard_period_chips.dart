import 'package:flutter/material.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Sprint 5 period selector — single-select chip row sitting under the
/// summary card. Custom range opens a [showDateRangePicker].
class DashboardPeriodChips extends StatelessWidget {
  const DashboardPeriodChips({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final DashboardPeriod selected;
  final ValueChanged<DashboardPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<_ChipSpec> presets = <_ChipSpec>[
      _ChipSpec(
        label: l.dashboardPeriodWeek,
        period: const DashboardPeriod.thisWeek(),
      ),
      _ChipSpec(
        label: l.dashboardPeriodMonth,
        period: const DashboardPeriod.thisMonth(),
      ),
      _ChipSpec(
        label: l.dashboardPeriod3Months,
        period: const DashboardPeriod.last3Months(),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          for (final _ChipSpec spec in presets) ...<Widget>[
            ChoiceChip(
              label: Text(spec.label),
              selected: selected.runtimeType == spec.period.runtimeType,
              onSelected: (bool v) {
                if (v) onChanged(spec.period);
              },
            ),
            const SizedBox(width: 8),
          ],
          ChoiceChip(
            label: Text(l.dashboardPeriodCustom),
            selected: selected is CustomPeriod,
            avatar: const Icon(Icons.calendar_today_rounded, size: 16),
            onSelected: (bool _) => _pickCustomRange(context, l),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange(
    BuildContext context,
    AppLocalizations l,
  ) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: selected is CustomPeriod
          ? DateTimeRange(
              start: (selected as CustomPeriod).from,
              end: (selected as CustomPeriod).to,
            )
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
      helpText: l.dashboardPickRangeTitle,
    );
    if (picked == null) return;
    onChanged(DashboardPeriod.custom(from: picked.start, to: picked.end));
  }
}

class _ChipSpec {
  const _ChipSpec({required this.label, required this.period});

  final String label;
  final DashboardPeriod period;
}
