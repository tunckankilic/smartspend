import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_filter.dart';
import 'package:smartspend/features/expenses/domain/entities/expense_summary.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/delete_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_summary.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_list_bloc.dart';

class _MockRepo extends Mock implements ExpenseRepository {}

class _FakeFilter extends Fake implements ExpenseFilter {}

class _FakeDeleteParams extends Fake implements DeleteExpenseParams {}

class _FakeSummaryParams extends Fake implements GetExpenseSummaryParams {}

const Category _market = Category(
  id: 1,
  name: 'Market',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

Expense _expense({
  required int id,
  Category category = _market,
  int amount = 1000,
  DateTime? date,
}) {
  return Expense(
    id: id,
    amount: amount,
    category: category,
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
    registerFallbackValue(_FakeDeleteParams());
    registerFallbackValue(_FakeSummaryParams());
  });

  late _MockRepo repo;
  late StreamController<List<Expense>> streamCtrl;

  ExpenseListBloc build() {
    return ExpenseListBloc(
      repository: repo,
      getSummary: GetExpenseSummaryUseCase(repo),
      deleteExpense: DeleteExpenseUseCase(repo),
    );
  }

  setUp(() {
    repo = _MockRepo();
    streamCtrl = StreamController<List<Expense>>.broadcast();
    when(() => repo.watchExpenses(any())).thenAnswer((_) => streamCtrl.stream);
    when(() => repo.getSummary(any())).thenAnswer(
      (_) async => const Right<Failure, ExpenseSummary>(ExpenseSummary.empty),
    );
    when(() => repo.deleteExpense(any())).thenAnswer(
      (_) async => const Right<Failure, void>(null),
    );
  });

  tearDown(() async {
    await streamCtrl.close();
  });

  group('subscription lifecycle', () {
    blocTest<ExpenseListBloc, ExpenseListState>(
      'should emit Loading then Loaded when the stream fires',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[_expense(id: 1)]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => <Matcher>[
        isA<ExpenseListLoading>(),
        isA<ExpenseListLoaded>().having(
          (ExpenseListLoaded s) => s.expenses.length,
          'expenses',
          1,
        ),
      ],
    );

    blocTest<ExpenseListBloc, ExpenseListState>(
      'should surface stream errors as ExpenseListError on first emission',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.addError(Exception('boom'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      expect: () => <Matcher>[
        isA<ExpenseListLoading>(),
        isA<ExpenseListError>(),
      ],
    );

    blocTest<ExpenseListBloc, ExpenseListState>(
      'should surface stream errors as transient banner once Loaded',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[_expense(id: 1)]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        streamCtrl.addError(Exception('later'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (ExpenseListBloc b) {
        final ExpenseListState s = b.state;
        expect(s, isA<ExpenseListLoaded>());
        expect((s as ExpenseListLoaded).transientError, isNotNull);
      },
    );
  });

  group('filter mutators', () {
    blocTest<ExpenseListBloc, ExpenseListState>(
      'should toggle a category id in/out of the filter set',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const CategoryFilterToggled(categoryId: 2));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const CategoryFilterToggled(categoryId: 2));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (ExpenseListBloc b) {
        expect(b.state.filter.categoryIds, isEmpty);
      },
    );

    blocTest<ExpenseListBloc, ExpenseListState>(
      'should re-subscribe with the new filter on FilterChanged',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[_expense(id: 1)]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(
          FilterChanged(
            filter: ExpenseFilter(
              dateFrom: DateTime.utc(2026, 5, 1),
              categoryIds: const <int>{1},
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (ExpenseListBloc b) {
        verify(() => repo.watchExpenses(any())).called(2);
        expect(b.state.filter.dateFrom, DateTime.utc(2026, 5, 1));
        expect(b.state.filter.categoryIds, <int>{1});
      },
    );

    blocTest<ExpenseListBloc, ExpenseListState>(
      'FiltersCleared should reset to ExpenseFilter.empty',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(
          const FilterChanged(
            filter: ExpenseFilter(categoryIds: <int>{42}),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const FiltersCleared());
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (ExpenseListBloc b) {
        expect(b.state.filter, ExpenseFilter.empty);
      },
    );

    blocTest<ExpenseListBloc, ExpenseListState>(
      'SortChanged should update the filter snapshot',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const SortChanged(order: ExpenseSortOrder.amountDesc));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (ExpenseListBloc b) {
        expect(b.state.filter.sortOrder, ExpenseSortOrder.amountDesc);
      },
    );
  });

  group('search debounce', () {
    blocTest<ExpenseListBloc, ExpenseListState>(
      'should debounce rapid SearchQueried events',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // The first watchExpenses call is the initial subscription. The
        // remaining keystrokes should collapse into a single second call
        // once the 300 ms debounce settles.
        b
          ..add(const SearchQueried(query: 'k'))
          ..add(const SearchQueried(query: 'ka'))
          ..add(const SearchQueried(query: 'kah'))
          ..add(const SearchQueried(query: 'kahve'));
        await Future<void>.delayed(const Duration(milliseconds: 450));
      },
      verify: (ExpenseListBloc b) {
        // Exactly two watch calls: initial subscribe + one after debounce.
        verify(() => repo.watchExpenses(any())).called(2);
        expect(b.state.filter.searchQuery, 'kahve');
      },
    );
  });

  group('delete', () {
    blocTest<ExpenseListBloc, ExpenseListState>(
      'should delegate ExpenseDeleted to the use case',
      build: build,
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[_expense(id: 7)]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const ExpenseDeleted(id: 7));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (_) {
        verify(() => repo.deleteExpense(7)).called(1);
      },
    );

    blocTest<ExpenseListBloc, ExpenseListState>(
      'should set transientError when delete fails',
      build: () {
        when(() => repo.deleteExpense(any())).thenAnswer(
          (_) async => const Left<Failure, void>(
            CacheFailure(message: 'boom'),
          ),
        );
        return build();
      },
      act: (ExpenseListBloc b) async {
        b.add(const ExpensesSubscribed());
        await Future<void>.delayed(Duration.zero);
        streamCtrl.add(<Expense>[_expense(id: 9)]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const ExpenseDeleted(id: 9));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      verify: (ExpenseListBloc b) {
        final ExpenseListState s = b.state;
        expect(s, isA<ExpenseListLoaded>());
        expect((s as ExpenseListLoaded).transientError, isNotNull);
      },
    );
  });
}
