import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/entities/budget_period.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';
import 'package:smartspend/features/budget/domain/usecases/create_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/delete_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/update_budget.dart';
import 'package:smartspend/features/budget/domain/usecases/watch_budgets.dart';
import 'package:smartspend/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categories/domain/repositories/category_repository.dart';
import 'package:smartspend/features/categories/domain/usecases/list_categories.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';

class _MockBudgetRepo extends Mock implements BudgetRepository {}

class _MockExpenseRepo extends Mock implements ExpenseRepository {}

class _MockCatRepo extends Mock implements CategoryRepository {}

class _MockNotifications extends Mock implements NotificationService {}

class _FakeFilter extends Fake implements ExpenseFilter {}

const Category _market = Category(
  id: 1,
  name: 'Market',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

Budget _budget({
  int id = 1,
  int amount = 100000,
  int? categoryId = 1,
  BudgetPeriod period = BudgetPeriod.monthly,
}) {
  return Budget(
    id: id,
    amountMinor: amount,
    period: period,
    startDate: DateTime.utc(2026, 5, 1),
    isActive: true,
    categoryId: categoryId,
  );
}

Expense _exp({
  int id = 1,
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
  setUpAll(() {
    registerFallbackValue(_FakeFilter());
    // mocktail needs sentinel values for non-primitive types passed via
    // `any(named: ...)`.
    registerFallbackValue(BudgetPeriod.monthly);
    registerFallbackValue(DateTime.utc(2026, 1, 1));
  });

  late _MockBudgetRepo budgetRepo;
  late _MockExpenseRepo expenseRepo;
  late _MockCatRepo catRepo;
  late _MockNotifications notifications;
  late StreamController<List<Budget>> budgetCtrl;
  late StreamController<List<Expense>> expenseCtrl;
  final DateTime now = DateTime.utc(2026, 5, 24, 12);

  BudgetBloc build() {
    return BudgetBloc(
      watchBudgets: WatchBudgetsUseCase(budgetRepo),
      createBudget: CreateBudgetUseCase(budgetRepo),
      updateBudget: UpdateBudgetUseCase(budgetRepo),
      deleteBudget: DeleteBudgetUseCase(budgetRepo),
      expenseRepository: expenseRepo,
      listCategories: ListCategoriesUseCase(catRepo),
      notifications: notifications,
      now: () => now,
    );
  }

  setUp(() {
    budgetRepo = _MockBudgetRepo();
    expenseRepo = _MockExpenseRepo();
    catRepo = _MockCatRepo();
    notifications = _MockNotifications();
    budgetCtrl = StreamController<List<Budget>>.broadcast();
    expenseCtrl = StreamController<List<Expense>>.broadcast();

    when(() => budgetRepo.watchActiveBudgets())
        .thenAnswer((_) => budgetCtrl.stream);
    when(() => expenseRepo.watchExpenses(any()))
        .thenAnswer((_) => expenseCtrl.stream);
    when(() => catRepo.listAll()).thenAnswer(
      (_) async => const Right<Failure, List<Category>>(<Category>[_market]),
    );
    when(() => notifications.hasPermission())
        .thenAnswer((_) async => true);
    when(() => notifications.requestPermissions())
        .thenAnswer((_) async => true);
    when(() => notifications.showBudgetWarning(
          budgetId: any(named: 'budgetId'),
          percentSpent: any(named: 'percentSpent'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        )).thenAnswer((_) async {});
    when(() => budgetRepo.createBudget(
          amountMinor: any(named: 'amountMinor'),
          period: any(named: 'period'),
          startDate: any(named: 'startDate'),
          categoryId: any(named: 'categoryId'),
        )).thenAnswer((_) async => const Right<Failure, int>(99));
    when(() => budgetRepo.updateBudget(
          id: any(named: 'id'),
          amountMinor: any(named: 'amountMinor'),
          period: any(named: 'period'),
          startDate: any(named: 'startDate'),
          isActive: any(named: 'isActive'),
        )).thenAnswer((_) async => const Right<Failure, void>(null));
    when(() => budgetRepo.deleteBudget(any()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
  });

  tearDown(() async {
    await budgetCtrl.close();
    await expenseCtrl.close();
  });

  group('BudgetBloc', () {
    blocTest<BudgetBloc, BudgetState>(
      'should emit Loaded with composed snapshots after both streams tick',
      build: build,
      act: (BudgetBloc b) async {
        b.add(const BudgetSubscribed());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        budgetCtrl.add(<Budget>[_budget()]);
        expenseCtrl.add(<Expense>[_exp(amount: 30000)]);
      },
      wait: const Duration(milliseconds: 80),
      verify: (BudgetBloc b) {
        final loaded = b.state as BudgetLoaded;
        expect(loaded.snapshots, hasLength(1));
        expect(loaded.snapshots.first.status.spentMinor, 30000);
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'should suppress notifications on the baseline rebuild',
      build: build,
      act: (BudgetBloc b) async {
        b.add(const BudgetSubscribed());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        budgetCtrl.add(<Budget>[_budget()]);
        // Already at 90% on first emit — must NOT fire.
        expenseCtrl.add(<Expense>[_exp(amount: 90000)]);
      },
      wait: const Duration(milliseconds: 80),
      verify: (BudgetBloc _) {
        verifyNever(
          () => notifications.showBudgetWarning(
            budgetId: any(named: 'budgetId'),
            percentSpent: any(named: 'percentSpent'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        );
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'should fire showBudgetWarning when a threshold is freshly crossed',
      build: build,
      act: (BudgetBloc b) async {
        b.add(const BudgetSubscribed());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        budgetCtrl.add(<Budget>[_budget()]);
        // Baseline emit at 30 %.
        expenseCtrl.add(<Expense>[_exp(amount: 30000)]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // Jump to 90 % — fresh 80% threshold.
        expenseCtrl.add(<Expense>[
          _exp(amount: 30000),
          _exp(id: 2, amount: 60000),
        ]);
      },
      wait: const Duration(milliseconds: 100),
      verify: (BudgetBloc _) {
        verify(
          () => notifications.showBudgetWarning(
            budgetId: 1,
            percentSpent: any(named: 'percentSpent'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        ).called(1);
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'should not re-fire a threshold that was already crossed',
      build: build,
      act: (BudgetBloc b) async {
        b.add(const BudgetSubscribed());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        budgetCtrl.add(<Budget>[_budget()]);
        expenseCtrl.add(<Expense>[_exp(amount: 30000)]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expenseCtrl.add(<Expense>[_exp(amount: 85000)]); // 85 %
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expenseCtrl.add(<Expense>[_exp(amount: 90000)]); // still in 80-100
      },
      wait: const Duration(milliseconds: 120),
      verify: (BudgetBloc _) {
        verify(
          () => notifications.showBudgetWarning(
            budgetId: any(named: 'budgetId'),
            percentSpent: any(named: 'percentSpent'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        ).called(1);
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'should not fire when notifications are disabled',
      setUp: () {
        when(() => notifications.hasPermission())
            .thenAnswer((_) async => false);
      },
      build: build,
      act: (BudgetBloc b) async {
        b.add(const BudgetSubscribed());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        budgetCtrl.add(<Budget>[_budget()]);
        expenseCtrl.add(<Expense>[_exp(amount: 30000)]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expenseCtrl.add(<Expense>[_exp(amount: 90000)]);
      },
      wait: const Duration(milliseconds: 100),
      verify: (BudgetBloc _) {
        verifyNever(
          () => notifications.showBudgetWarning(
            budgetId: any(named: 'budgetId'),
            percentSpent: any(named: 'percentSpent'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        );
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'BudgetCreated should call the repository with the params',
      build: build,
      act: (BudgetBloc b) {
        b.add(
          BudgetCreated(
            amountMinor: 50000,
            period: BudgetPeriod.monthly,
            startDate: DateTime.utc(2026, 5, 1),
            categoryId: 1,
          ),
        );
      },
      wait: const Duration(milliseconds: 30),
      verify: (BudgetBloc _) {
        verify(
          () => budgetRepo.createBudget(
            amountMinor: 50000,
            period: BudgetPeriod.monthly,
            startDate: DateTime.utc(2026, 5, 1),
            categoryId: 1,
          ),
        ).called(1);
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'BudgetUpdated should call the repository with the patch',
      build: build,
      act: (BudgetBloc b) {
        b.add(
          const BudgetUpdated(
            id: 7,
            amountMinor: 75000,
            period: BudgetPeriod.weekly,
          ),
        );
      },
      wait: const Duration(milliseconds: 30),
      verify: (BudgetBloc _) {
        verify(
          () => budgetRepo.updateBudget(
            id: 7,
            amountMinor: 75000,
            period: BudgetPeriod.weekly,
            startDate: null,
            isActive: null,
          ),
        ).called(1);
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'BudgetDeleted should call the repository with the id',
      build: build,
      act: (BudgetBloc b) => b.add(const BudgetDeleted(id: 42)),
      wait: const Duration(milliseconds: 30),
      verify: (BudgetBloc _) {
        verify(() => budgetRepo.deleteBudget(42)).called(1);
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'BudgetPermissionRequested should request and propagate the flag',
      setUp: () {
        when(notifications.hasPermission).thenAnswer((_) async => false);
        when(notifications.requestPermissions)
            .thenAnswer((_) async => true);
      },
      build: build,
      act: (BudgetBloc b) async {
        b.add(const BudgetSubscribed());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const BudgetPermissionRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (BudgetBloc b) {
        if (b.state is BudgetLoaded) {
          expect(
            (b.state as BudgetLoaded).notificationsEnabled,
            isTrue,
          );
        } else if (b.state is BudgetLoading) {
          expect(
            (b.state as BudgetLoading).notificationsEnabled,
            isTrue,
          );
        }
      },
    );

    blocTest<BudgetBloc, BudgetState>(
      'a stream error should surface as BudgetError',
      build: build,
      act: (BudgetBloc b) async {
        b.add(const BudgetSubscribed());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        budgetCtrl.addError(StateError('drift exploded'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (BudgetBloc b) {
        expect(b.state, isA<BudgetError>());
      },
    );
  });
}
