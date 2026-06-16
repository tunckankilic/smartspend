import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// Builds the dashboard payload for a single [DashboardPeriod].
///
/// Calls [ExpenseRepository] twice — once for the current window
/// (full expense list, used for daily totals + recent + by-category +
/// total) and once for the previous window (summary only, used for the
/// delta).
class GetDashboardSnapshotUseCase
    implements UseCase<DashboardSnapshot, GetDashboardSnapshotParams> {
  GetDashboardSnapshotUseCase(this._repository, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final ExpenseRepository _repository;
  final DateTime Function() _now;

  @override
  Future<Either<Failure, DashboardSnapshot>> call(
    GetDashboardSnapshotParams params,
  ) async {
    final DateTime now = _now();
    final DateRange current = params.period.resolve(now);
    final DateRange previous = params.period.resolvePrevious(now);

    final Either<Failure, List<Expense>> currentExpenses =
        await _repository.getExpenses(current.toFilter());
    if (currentExpenses.isLeft()) {
      return left(
        currentExpenses.swap().getOrElse(
              () => const CacheFailure(message: 'dashboard.snapshotFailed'),
            ),
      );
    }

    final Either<Failure, ExpenseSummary> previousSummary =
        await _repository.getSummary(previous.toFilter());
    if (previousSummary.isLeft()) {
      return left(
        previousSummary.swap().getOrElse(
              () => const CacheFailure(message: 'dashboard.snapshotFailed'),
            ),
      );
    }

    final List<Expense> expenses =
        currentExpenses.getOrElse(() => const <Expense>[]);
    final ExpenseSummary prevSum = previousSummary.getOrElse(
      () => ExpenseSummary.empty,
    );

    return right(
      _build(
        expenses: expenses,
        previousSummary: prevSum,
        range: current,
      ),
    );
  }

  DashboardSnapshot _build({
    required List<Expense> expenses,
    required ExpenseSummary previousSummary,
    required DateRange range,
  }) {
    if (expenses.isEmpty) {
      return DashboardSnapshot(
        currency: previousSummary.currency,
        currentTotalMinor: 0,
        previousTotalMinor: previousSummary.totalMinor,
        byCategoryCurrent: const <int, int>{},
        byCategoryPrevious: previousSummary.byCategory,
        dailyTotals: _zeroFilledDays(range),
        recentExpenses: const <Expense>[],
        topCategoryId: null,
        expenseCount: 0,
      );
    }

    int total = 0;
    final Map<int, int> byCategory = <int, int>{};
    final Map<DateTime, int> daily = _zeroFilledDays(range);
    final Map<String, int> currencyVotes = <String, int>{};
    final Map<int, int> byWeekday = <int, int>{};
    final Map<String, TagFrequencyAggregate> tagFreq =
        <String, TagFrequencyAggregate>{};

    for (final Expense e in expenses) {
      total += e.amount;
      byCategory.update(
        e.category.id,
        (int v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
      final DateTime bucket = _dayBucket(e.date);
      daily.update(bucket, (int v) => v + e.amount, ifAbsent: () => e.amount);
      currencyVotes.update(
        e.currency,
        (int v) => v + 1,
        ifAbsent: () => 1,
      );
      // Day-of-week aggregate (ISO: Mon=1..Sun=7) — driver for
      // [DayOfWeekInsight].
      byWeekday.update(
        e.date.toUtc().weekday,
        (int v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
      // Tag frequency aggregate — case-insensitive grouping with
      // original casing preserved on the first seen key.
      for (final String tag in e.tags) {
        final String key = tag.trim();
        if (key.isEmpty) continue;
        final String lower = key.toLowerCase();
        final String existing = tagFreq.keys.firstWhere(
          (String k) => k.toLowerCase() == lower,
          orElse: () => '',
        );
        if (existing.isNotEmpty) {
          tagFreq[existing] = tagFreq[existing]!.add(e.amount);
        } else {
          tagFreq[key] = TagFrequencyAggregate(
            count: 1,
            totalMinor: e.amount,
          );
        }
      }
    }

    final String currency = currencyVotes.entries
        .reduce((MapEntry<String, int> a, MapEntry<String, int> b) =>
            a.value >= b.value ? a : b)
        .key;

    final int topCategoryId = byCategory.entries
        .reduce((MapEntry<int, int> a, MapEntry<int, int> b) =>
            a.value >= b.value ? a : b)
        .key;

    final List<Expense> sortedByDate = <Expense>[...expenses]
      ..sort((Expense a, Expense b) => b.date.compareTo(a.date));
    final List<Expense> recent = sortedByDate.take(5).toList(growable: false);

    return DashboardSnapshot(
      currency: currency,
      currentTotalMinor: total,
      previousTotalMinor: previousSummary.totalMinor,
      byCategoryCurrent: byCategory,
      byCategoryPrevious: previousSummary.byCategory,
      dailyTotals: daily,
      recentExpenses: recent,
      topCategoryId: topCategoryId,
      expenseCount: expenses.length,
      byWeekdayMinor: byWeekday,
      tagFrequency: tagFreq,
    );
  }

  Map<DateTime, int> _zeroFilledDays(DateRange range) {
    final Map<DateTime, int> out = <DateTime, int>{};
    DateTime cursor = range.start;
    while (cursor.isBefore(range.endExclusive)) {
      out[cursor] = 0;
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }

  DateTime _dayBucket(DateTime dt) {
    final DateTime u = dt.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }
}

class GetDashboardSnapshotParams extends Equatable {
  const GetDashboardSnapshotParams({
    this.period = const DashboardPeriod.thisMonth(),
  });

  final DashboardPeriod period;

  @override
  List<Object?> get props => <Object?>[period];
}
