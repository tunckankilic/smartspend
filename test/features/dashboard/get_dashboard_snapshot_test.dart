import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_snapshot.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';

class _MockRepo extends Mock implements ExpenseRepository {}

class _FakeFilter extends Fake implements ExpenseFilter {}

const Category _market = Category(
  id: 1,
  name: 'Market',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);
const Category _coffee = Category(
  id: 2,
  name: 'Coffee',
  icon: 'coffee',
  color: 0xFF795548,
  isCustom: false,
);

Expense _exp({
  required int id,
  Category cat = _market,
  int amount = 1000,
  String currency = 'TRY',
  DateTime? date,
}) {
  return Expense(
    id: id,
    amount: amount,
    category: cat,
    date: date ?? DateTime.utc(2026, 5, 20),
    currency: currency,
    isManual: true,
    isRecurring: false,
    isPendingSync: false,
  );
}

void main() {
  setUpAll(() => registerFallbackValue(_FakeFilter()));

  late _MockRepo repo;
  late GetDashboardSnapshotUseCase useCase;
  final DateTime now = DateTime.utc(2026, 5, 27, 9);

  setUp(() {
    repo = _MockRepo();
    useCase = GetDashboardSnapshotUseCase(repo, now: () => now);
  });

  test(
    'should aggregate current totals, byCategory, dailyTotals, recent',
    () async {
      when(() => repo.getExpenses(any())).thenAnswer(
        (_) async => Right<Failure, List<Expense>>(<Expense>[
          _exp(id: 1, amount: 5000, date: DateTime.utc(2026, 5, 26)),
          _exp(id: 2, amount: 3000, date: DateTime.utc(2026, 5, 26)),
          _exp(
            id: 3,
            cat: _coffee,
            amount: 4000,
            date: DateTime.utc(2026, 5, 27),
          ),
        ]),
      );
      when(() => repo.getSummary(any())).thenAnswer(
        (_) async => const Right<Failure, ExpenseSummary>(
          ExpenseSummary(
            totalMinor: 6000,
            currency: 'TRY',
            byCategory: <int, int>{1: 6000},
            count: 1,
          ),
        ),
      );

      final res = await useCase(
        const GetDashboardSnapshotParams(period: DashboardPeriod.thisWeek()),
      );
      final DashboardSnapshot snap = res.getOrElse(
        () => fail('expected Right'),
      );
      expect(snap.currentTotalMinor, 12000);
      expect(snap.previousTotalMinor, 6000);
      expect(snap.byCategoryCurrent, <int, int>{1: 8000, 2: 4000});
      expect(snap.expenseCount, 3);
      expect(snap.topCategoryId, 1);
      expect(snap.recentExpenses.first.id, 3); // newest by date desc
    },
  );

  test('should zero-fill daily totals across the period', () async {
    when(() => repo.getExpenses(any())).thenAnswer(
      (_) async => Right<Failure, List<Expense>>(<Expense>[
        _exp(id: 1, amount: 1000, date: DateTime.utc(2026, 5, 27)),
      ]),
    );
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
    );

    final res = await useCase(
      const GetDashboardSnapshotParams(period: DashboardPeriod.thisWeek()),
    );
    final DashboardSnapshot snap = res.getOrElse(() => fail('expected Right'));
    // Mon 25 → Sun 31 = 7 day buckets.
    expect(snap.dailyTotals.length, 7);
    expect(snap.dailyTotals[DateTime.utc(2026, 5, 25)], 0);
    expect(snap.dailyTotals[DateTime.utc(2026, 5, 27)], 1000);
  });

  test('should emit an empty snapshot when there are no expenses', () async {
    when(() => repo.getExpenses(any())).thenAnswer(
      (_) async => const Right<Failure, List<Expense>>(<Expense>[]),
    );
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
    );

    final res = await useCase(const GetDashboardSnapshotParams());
    final DashboardSnapshot snap = res.getOrElse(() => fail('expected Right'));
    expect(snap.isEmpty, isTrue);
    expect(snap.expenseCount, 0);
    expect(snap.topCategoryId, isNull);
    expect(snap.recentExpenses, isEmpty);
    expect(snap.deltaPercent, isNull); // prev=0
  });

  test('should compute a signed deltaPercent when prev > 0', () async {
    when(() => repo.getExpenses(any())).thenAnswer(
      (_) async => Right<Failure, List<Expense>>(<Expense>[
        _exp(id: 1, amount: 12000, date: DateTime.utc(2026, 5, 25)),
      ]),
    );
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(
        ExpenseSummary(
          totalMinor: 10000,
          currency: 'TRY',
          byCategory: <int, int>{1: 10000},
          count: 1,
        ),
      ),
    );

    final res = await useCase(const GetDashboardSnapshotParams());
    final DashboardSnapshot snap = res.getOrElse(() => fail('expected Right'));
    expect(snap.deltaPercent, closeTo(20.0, 0.01));
  });

  test('should keep at most 5 recent expenses, newest-first', () async {
    when(() => repo.getExpenses(any())).thenAnswer(
      (_) async => Right<Failure, List<Expense>>(<Expense>[
        for (int i = 0; i < 8; i++)
          _exp(id: i, amount: 100, date: DateTime.utc(2026, 5, 20 + i)),
      ]),
    );
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
    );

    final res = await useCase(
      const GetDashboardSnapshotParams(period: DashboardPeriod.thisMonth()),
    );
    final DashboardSnapshot snap = res.getOrElse(() => fail('expected Right'));
    expect(snap.recentExpenses.length, 5);
    expect(snap.recentExpenses.first.id, 7);
    expect(snap.recentExpenses.last.id, 3);
  });

  test('should propagate a Left when the current-period read fails',
      () async {
    when(() => repo.getExpenses(any())).thenAnswer(
      (_) async => const Left<Failure, List<Expense>>(
        CacheFailure(message: 'drift kapatıldı'),
      ),
    );
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
    );

    final res = await useCase(const GetDashboardSnapshotParams());
    expect(res.isLeft(), isTrue);
  });

  test('should pick the most common currency from the expenses', () async {
    when(() => repo.getExpenses(any())).thenAnswer(
      (_) async => Right<Failure, List<Expense>>(<Expense>[
        _exp(id: 1, currency: 'EUR'),
        _exp(id: 2, currency: 'EUR'),
        _exp(id: 3, currency: 'TRY'),
      ]),
    );
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
    );

    final res = await useCase(const GetDashboardSnapshotParams());
    final snap = res.getOrElse(() => fail('expected Right'));
    expect(snap.currency, 'EUR');
  });
}
