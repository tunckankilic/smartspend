import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/presentation/bloc/dashboard_bloc.dart';

/// Equality contracts for [DashboardEvent] subtypes.
void main() {
  group('DashboardEvent equality', () {
    test('should treat value-less events as equal', () {
      expect(const DashboardSubscribed(), const DashboardSubscribed());
      expect(const DashboardRefreshed(), const DashboardRefreshed());
    });

    test('should compare DashboardPeriodChanged by period', () {
      expect(
        const DashboardPeriodChanged(period: DashboardPeriod.thisMonth()),
        const DashboardPeriodChanged(period: DashboardPeriod.thisMonth()),
      );
      expect(
        const DashboardPeriodChanged(period: DashboardPeriod.thisMonth()),
        isNot(
          const DashboardPeriodChanged(period: DashboardPeriod.thisWeek()),
        ),
      );
    });
  });
}
