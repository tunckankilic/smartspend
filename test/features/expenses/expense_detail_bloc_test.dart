import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/delete_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_expense_by_id.dart';
import 'package:smartspend/features/expenses/presentation/bloc/expense_detail_bloc.dart';

class _MockRepo extends Mock implements ExpenseRepository {}

class _FakeDeleteParams extends Fake implements DeleteExpenseParams {}

class _FakeGetByIdParams extends Fake implements GetExpenseByIdParams {}

const Category _market = Category(
  id: 1,
  name: 'Market',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

final Expense _expense = Expense(
  id: 42,
  amount: 1500,
  category: _market,
  date: DateTime.utc(2026, 5, 20),
  currency: 'TRY',
  isManual: true,
  isRecurring: false,
  isPendingSync: false,
);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDeleteParams());
    registerFallbackValue(_FakeGetByIdParams());
  });

  late _MockRepo repo;

  ExpenseDetailBloc build() => ExpenseDetailBloc(
        getExpenseById: GetExpenseByIdUseCase(repo),
        deleteExpense: DeleteExpenseUseCase(repo),
      );

  setUp(() {
    repo = _MockRepo();
  });

  blocTest<ExpenseDetailBloc, ExpenseDetailState>(
    'should emit Loading then Loaded when the row exists',
    build: () {
      when(() => repo.getExpenseById(42)).thenAnswer(
        (_) async => Right<Failure, Expense?>(_expense),
      );
      return build();
    },
    act: (ExpenseDetailBloc b) =>
        b.add(const ExpenseDetailRequested(id: 42)),
    expect: () => <Matcher>[
      isA<ExpenseDetailLoading>(),
      isA<ExpenseDetailLoaded>().having(
        (ExpenseDetailLoaded s) => s.expense?.id,
        'expense.id',
        42,
      ),
    ],
  );

  blocTest<ExpenseDetailBloc, ExpenseDetailState>(
    'should emit Loaded with null expense when id is missing',
    build: () {
      when(() => repo.getExpenseById(999)).thenAnswer(
        (_) async => const Right<Failure, Expense?>(null),
      );
      return build();
    },
    act: (ExpenseDetailBloc b) =>
        b.add(const ExpenseDetailRequested(id: 999)),
    expect: () => <Matcher>[
      isA<ExpenseDetailLoading>(),
      isA<ExpenseDetailLoaded>().having(
        (ExpenseDetailLoaded s) => s.expense,
        'expense',
        isNull,
      ),
    ],
  );

  blocTest<ExpenseDetailBloc, ExpenseDetailState>(
    'should emit Deleted after a successful delete',
    build: () {
      when(() => repo.getExpenseById(42)).thenAnswer(
        (_) async => Right<Failure, Expense?>(_expense),
      );
      when(() => repo.deleteExpense(42)).thenAnswer(
        (_) async => const Right<Failure, void>(null),
      );
      return build();
    },
    act: (ExpenseDetailBloc b) async {
      b.add(const ExpenseDetailRequested(id: 42));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const ExpenseDetailDeletedRequested());
    },
    skip: 2,
    expect: () => <Matcher>[isA<ExpenseDetailDeleted>()],
  );

  blocTest<ExpenseDetailBloc, ExpenseDetailState>(
    'should emit Error when delete fails',
    build: () {
      when(() => repo.getExpenseById(42)).thenAnswer(
        (_) async => Right<Failure, Expense?>(_expense),
      );
      when(() => repo.deleteExpense(42)).thenAnswer(
        (_) async => const Left<Failure, void>(CacheFailure(message: 'no')),
      );
      return build();
    },
    act: (ExpenseDetailBloc b) async {
      b.add(const ExpenseDetailRequested(id: 42));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      b.add(const ExpenseDetailDeletedRequested());
    },
    skip: 2,
    expect: () => <Matcher>[isA<ExpenseDetailError>()],
  );

  blocTest<ExpenseDetailBloc, ExpenseDetailState>(
    'should emit Error when getExpenseById fails',
    build: () {
      when(() => repo.getExpenseById(any())).thenAnswer(
        (_) async => const Left<Failure, Expense?>(
          CacheFailure(message: 'db blew up'),
        ),
      );
      return build();
    },
    act: (ExpenseDetailBloc b) =>
        b.add(const ExpenseDetailRequested(id: 1)),
    expect: () => <Matcher>[
      isA<ExpenseDetailLoading>(),
      isA<ExpenseDetailError>(),
    ],
  );
}
