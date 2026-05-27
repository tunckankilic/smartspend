import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/repositories/category_repository.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/dashboard/domain/entities/dashboard_period.dart';
import 'package:smartspend/features/dashboard/domain/usecases/get_dashboard_snapshot.dart';
import 'package:smartspend/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';

class _MockRepo extends Mock implements ExpenseRepository {}

class _MockCatRepo extends Mock implements CategoryRepository {}

class _FakeFilter extends Fake implements ExpenseFilter {}

const Category _market = Category(
  id: 1,
  name: 'Market',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

Expense _exp({
  required int id,
  int amount = 1000,
  DateTime? date,
}) {
  return Expense(
    id: id,
    amount: amount,
    category: _market,
    date: date ?? DateTime.utc(2026, 5, 20),
    currency: 'TRY',
    isManual: true,
    isRecurring: false,
    isPendingSync: false,
  );
}

void main() {
  setUpAll(() => registerFallbackValue(_FakeFilter()));

  late _MockRepo repo;
  late _MockCatRepo catRepo;
  late StreamController<List<Expense>> ctrl;
  final DateTime now = DateTime.utc(2026, 5, 27, 9);

  DashboardBloc build() {
    return DashboardBloc(
      repository: repo,
      getSnapshot: GetDashboardSnapshotUseCase(repo, now: () => now),
      listCategories: ListCategoriesUseCase(catRepo),
      now: () => now,
    );
  }

  setUp(() {
    repo = _MockRepo();
    catRepo = _MockCatRepo();
    ctrl = StreamController<List<Expense>>.broadcast();
    when(() => repo.watchExpenses(any())).thenAnswer((_) => ctrl.stream);
    when(() => repo.getExpenses(any())).thenAnswer(
      (_) async => const Right<Failure, List<Expense>>(<Expense>[]),
    );
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
    );
    when(catRepo.listAll).thenAnswer(
      (_) async =>
          const Right<Failure, List<Category>>(<Category>[_market]),
    );
  });

  tearDown(() async {
    await ctrl.close();
  });

  test('should start in DashboardInitial with thisMonth as default', () {
    final bloc = build();
    expect(bloc.state, isA<DashboardInitial>());
    expect(bloc.state.period, isA<ThisMonthPeriod>());
    bloc.close();
  });

  blocTest<DashboardBloc, DashboardState>(
    'should emit Loading → Loaded on DashboardSubscribed',
    build: build,
    act: (b) {
      b.add(const DashboardSubscribed());
      // Drift will emit naturally on subscribe — simulate that.
      Future<void>.microtask(() => ctrl.add(const <Expense>[]));
    },
    wait: const Duration(milliseconds: 50),
    expect: () => <Matcher>[
      isA<DashboardLoading>(),
      isA<DashboardLoaded>(),
    ],
  );

  blocTest<DashboardBloc, DashboardState>(
    'should expose an empty snapshot when no expenses are present',
    build: build,
    act: (b) {
      b.add(const DashboardSubscribed());
      Future<void>.microtask(() => ctrl.add(const <Expense>[]));
    },
    wait: const Duration(milliseconds: 50),
    verify: (b) {
      final s = b.state;
      expect(s, isA<DashboardLoaded>());
      expect((s as DashboardLoaded).snapshot.isEmpty, isTrue);
      expect(s.insight, isNull);
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should re-subscribe with a new filter when the period changes',
    build: build,
    act: (b) async {
      b.add(const DashboardSubscribed());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(
        const DashboardPeriodChanged(period: DashboardPeriod.thisWeek()),
      );
    },
    wait: const Duration(milliseconds: 100),
    verify: (b) {
      expect(b.state.period, isA<ThisWeekPeriod>());
      // watchExpenses called once for thisMonth + once for thisWeek.
      verify(() => repo.watchExpenses(any())).called(2);
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should hand the snapshot off to the insight engine on every tick',
    build: () {
      when(() => repo.getExpenses(any())).thenAnswer(
        (_) async => Right<Failure, List<Expense>>(<Expense>[
          _exp(id: 1, amount: 60000, date: DateTime.utc(2026, 5, 20)),
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
      return build();
    },
    act: (b) {
      b.add(const DashboardSubscribed());
      Future<void>.microtask(() => ctrl.add(const <Expense>[]));
    },
    wait: const Duration(milliseconds: 50),
    verify: (b) {
      final loaded = b.state as DashboardLoaded;
      expect(loaded.insight, isNotNull);
      expect(loaded.insight!.categoryId, 1);
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should surface DashboardError when the snapshot use case fails',
    build: () {
      when(() => repo.getExpenses(any())).thenAnswer(
        (_) async => const Left<Failure, List<Expense>>(
          CacheFailure(message: 'kapatıldı'),
        ),
      );
      return build();
    },
    act: (b) {
      b.add(const DashboardSubscribed());
      Future<void>.microtask(() => ctrl.add(const <Expense>[]));
    },
    wait: const Duration(milliseconds: 50),
    verify: (b) {
      expect(b.state, isA<DashboardError>());
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should surface DashboardError when the watch stream emits an error',
    build: build,
    act: (b) async {
      b.add(const DashboardSubscribed());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ctrl.addError(StateError('drift went away'));
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) {
      expect(b.state, isA<DashboardError>());
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should rebuild on DashboardRefreshed',
    build: build,
    act: (b) async {
      b.add(const DashboardSubscribed());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      b.add(const DashboardRefreshed());
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) {
      verify(() => repo.watchExpenses(any())).called(2);
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should pass categories through to the loaded state',
    build: build,
    act: (b) {
      b.add(const DashboardSubscribed());
      Future<void>.microtask(() => ctrl.add(const <Expense>[]));
    },
    wait: const Duration(milliseconds: 50),
    verify: (b) {
      final s = b.state as DashboardLoaded;
      expect(s.categories, contains(_market));
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should keep the same period across refresh',
    build: build,
    act: (b) async {
      b.add(const DashboardPeriodChanged(
        period: DashboardPeriod.last3Months(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const DashboardRefreshed());
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) {
      expect(b.state.period, isA<Last3MonthsPeriod>());
    },
  );

  blocTest<DashboardBloc, DashboardState>(
    'should tear down the subscription on close',
    build: build,
    act: (b) async {
      b.add(const DashboardSubscribed());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await b.close();
    },
    wait: const Duration(milliseconds: 80),
    verify: (b) {
      expect(ctrl.hasListener, isFalse);
    },
  );
}
