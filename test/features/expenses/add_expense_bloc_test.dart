import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/expenses/domain/entities/expense.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/add_expense.dart';
import 'package:smartspend/features/expenses/domain/usecases/get_all_tags.dart';
import 'package:smartspend/features/expenses/domain/usecases/update_expense.dart';
import 'package:smartspend/features/expenses/presentation/bloc/add_expense_bloc.dart';

import '../../helpers/test_database.dart';

class _MockRepo extends Mock implements ExpenseRepository {}

class _FakeAddParams extends Fake implements AddExpenseParams {}

class _FakeUpdateParams extends Fake implements UpdateExpenseParams {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAddParams());
    registerFallbackValue(_FakeUpdateParams());
  });

  late AppDatabase db;
  late _MockRepo repo;
  late int marketId;

  AddExpenseBloc build() => AddExpenseBloc(
        addExpense: AddExpenseUseCase(repo),
        updateExpense: UpdateExpenseUseCase(repo),
        getAllTags: GetAllTagsUseCase(repo),
        categoryDao: db.categoryDao,
      );

  setUp(() async {
    db = createTestDatabase();
    // Seed categories run as part of onCreate; make sure they're loaded.
    final List<drift_db.Category> cats = await db.categoryDao.getAll();
    marketId = cats
        .firstWhere(
          (drift_db.Category c) => c.name == 'Market',
          orElse: () => cats.first,
        )
        .id;

    repo = _MockRepo();
    when(() => repo.getAllTagNames()).thenAnswer(
      (_) async => const Right<Failure, List<String>>(<String>['kahve', 'iş']),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('bootstrap', () {
    blocTest<AddExpenseBloc, AddExpenseState>(
      'AddExpenseStarted should land in Ready with Market default',
      build: build,
      act: (AddExpenseBloc b) => b.add(const AddExpenseStarted()),
      expect: () => <Matcher>[
        isA<AddExpenseLoading>(),
        isA<AddExpenseReady>()
            .having((AddExpenseReady s) => s.mode, 'mode', AddExpenseMode.add)
            .having(
              (AddExpenseReady s) => s.category?.name,
              'default category',
              'Market',
            )
            .having(
              (AddExpenseReady s) => s.availableTags,
              'available tags',
              <String>['kahve', 'iş'],
            ),
      ],
    );

    blocTest<AddExpenseBloc, AddExpenseState>(
      'AddExpenseEditStarted should seed every field from the expense',
      build: build,
      act: (AddExpenseBloc b) async {
        final Expense source = Expense(
          id: 99,
          amount: 1500,
          category: Category(
            id: marketId,
            name: 'Market',
            icon: 'shopping_cart',
            color: 0xFF4CAF50,
            isCustom: false,
          ),
          date: DateTime.utc(2026, 5, 22),
          currency: 'TRY',
          isManual: true,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.monthly,
          isPendingSync: false,
          tags: const <String>['kira'],
          note: 'kira ödemesi',
        );
        b.add(AddExpenseEditStarted(expense: source));
      },
      expect: () => <Matcher>[
        isA<AddExpenseLoading>(),
        isA<AddExpenseReady>()
            .having((AddExpenseReady s) => s.mode, 'mode', AddExpenseMode.edit)
            .having((AddExpenseReady s) => s.editingId, 'editingId', 99)
            .having(
              (AddExpenseReady s) => s.amountInput,
              'amountInput',
              '15.00',
            )
            .having(
              (AddExpenseReady s) => s.amountMinor,
              'amountMinor',
              1500,
            )
            .having((AddExpenseReady s) => s.note, 'note', 'kira ödemesi')
            .having(
              (AddExpenseReady s) => s.tags,
              'tags',
              <String>['kira'],
            )
            .having(
              (AddExpenseReady s) => s.isRecurring,
              'isRecurring',
              isTrue,
            )
            .having(
              (AddExpenseReady s) => s.recurringPeriod,
              'recurringPeriod',
              RecurringPeriod.monthly,
            ),
      ],
    );
  });

  group('field mutations', () {
    blocTest<AddExpenseBloc, AddExpenseState>(
      'AmountChanged should parse minor units',
      build: build,
      act: (AddExpenseBloc b) async {
        b.add(const AddExpenseStarted());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b.add(const AddExpenseAmountChanged(input: '12,50'));
      },
      verify: (AddExpenseBloc b) {
        final AddExpenseReady s = b.state as AddExpenseReady;
        expect(s.amountMinor, 1250);
        expect(s.amountInput, '12,50');
      },
    );

    blocTest<AddExpenseBloc, AddExpenseState>(
      'TagAdded should de-dupe case-insensitively',
      build: build,
      act: (AddExpenseBloc b) async {
        b.add(const AddExpenseStarted());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b
          ..add(const AddExpenseTagAdded(tag: 'Kahve'))
          ..add(const AddExpenseTagAdded(tag: 'kahve'))
          ..add(const AddExpenseTagAdded(tag: ' İş '));
      },
      verify: (AddExpenseBloc b) {
        final AddExpenseReady s = b.state as AddExpenseReady;
        expect(s.tags, <String>['Kahve', 'İş']);
      },
    );

    blocTest<AddExpenseBloc, AddExpenseState>(
      'RecurringToggled off should clear the period',
      build: build,
      act: (AddExpenseBloc b) async {
        b.add(const AddExpenseStarted());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b
          ..add(const AddExpenseRecurringToggled(value: true))
          ..add(const AddExpensePeriodChanged(period: RecurringPeriod.weekly))
          ..add(const AddExpenseRecurringToggled(value: false));
      },
      verify: (AddExpenseBloc b) {
        final AddExpenseReady s = b.state as AddExpenseReady;
        expect(s.isRecurring, isFalse);
        expect(s.recurringPeriod, isNull);
      },
    );
  });

  group('submit — validation', () {
    blocTest<AddExpenseBloc, AddExpenseState>(
      'should surface invalidAmount + futureDate errors',
      build: build,
      act: (AddExpenseBloc b) async {
        b.add(const AddExpenseStarted());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b
          ..add(
            AddExpenseDateSelected(
              date: DateTime.now().add(const Duration(days: 1)),
            ),
          )
          ..add(const AddExpenseSubmitted());
      },
      verify: (AddExpenseBloc b) {
        final AddExpenseReady s = b.state as AddExpenseReady;
        expect(s.validationErrors, <AddExpenseValidationError>{
          AddExpenseValidationError.invalidAmount,
          AddExpenseValidationError.futureDate,
        });
        verifyNever(() => repo.addExpense(
              amount: any(named: 'amount'),
              categoryId: any(named: 'categoryId'),
              date: any(named: 'date'),
              isManual: any(named: 'isManual'),
            ));
      },
    );

  });

  group('submit — happy paths', () {
    blocTest<AddExpenseBloc, AddExpenseState>(
      'should call repo.addExpense and emit AddExpenseSaved',
      build: () {
        when(() => repo.addExpense(
              amount: any(named: 'amount'),
              categoryId: any(named: 'categoryId'),
              date: any(named: 'date'),
              isManual: any(named: 'isManual'),
              note: any(named: 'note'),
              receiptId: any(named: 'receiptId'),
              isRecurring: any(named: 'isRecurring'),
              recurringPeriod: any(named: 'recurringPeriod'),
              tags: any(named: 'tags'),
            )).thenAnswer((_) async => const Right<Failure, int>(7));
        return build();
      },
      act: (AddExpenseBloc b) async {
        b.add(const AddExpenseStarted());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b
          ..add(const AddExpenseAmountChanged(input: '12,50'))
          ..add(const AddExpenseTagAdded(tag: 'lunch'))
          ..add(const AddExpenseSubmitted());
      },
      verify: (AddExpenseBloc b) {
        expect(b.state, isA<AddExpenseSaved>());
        expect((b.state as AddExpenseSaved).savedId, 7);
        verify(() => repo.addExpense(
              amount: 1250,
              categoryId: marketId,
              date: any(named: 'date'),
              isManual: true,
              note: any(named: 'note'),
              receiptId: any(named: 'receiptId'),
              isRecurring: false,
              recurringPeriod: any(named: 'recurringPeriod'),
              tags: <String>['lunch'],
            )).called(1);
      },
    );

    blocTest<AddExpenseBloc, AddExpenseState>(
      'should call repo.updateExpense in edit mode',
      build: () {
        when(() => repo.updateExpense(
              id: any(named: 'id'),
              amount: any(named: 'amount'),
              categoryId: any(named: 'categoryId'),
              date: any(named: 'date'),
              note: any(named: 'note'),
              clearNote: any(named: 'clearNote'),
              isRecurring: any(named: 'isRecurring'),
              recurringPeriod: any(named: 'recurringPeriod'),
              clearRecurringPeriod: any(named: 'clearRecurringPeriod'),
              tags: any(named: 'tags'),
            )).thenAnswer((_) async => const Right<Failure, void>(null));
        return build();
      },
      act: (AddExpenseBloc b) async {
        b.add(
          AddExpenseEditStarted(
            expense: Expense(
              id: 5,
              amount: 1000,
              category: Category(
                id: marketId,
                name: 'Market',
                icon: 'shopping_cart',
                color: 0xFF4CAF50,
                isCustom: false,
              ),
              date: DateTime.utc(2026, 5, 1),
              currency: 'TRY',
              isManual: true,
              isRecurring: false,
              isPendingSync: false,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b
          ..add(const AddExpenseAmountChanged(input: '25,00'))
          ..add(const AddExpenseSubmitted());
      },
      verify: (AddExpenseBloc b) {
        expect(b.state, isA<AddExpenseSaved>());
        verify(() => repo.updateExpense(
              id: 5,
              amount: 2500,
              categoryId: marketId,
              date: any(named: 'date'),
              note: any(named: 'note'),
              clearNote: any(named: 'clearNote'),
              isRecurring: false,
              recurringPeriod: any(named: 'recurringPeriod'),
              clearRecurringPeriod: true,
              tags: any(named: 'tags'),
            )).called(1);
      },
    );

    blocTest<AddExpenseBloc, AddExpenseState>(
      'should emit Failure + restore Ready when add fails',
      build: () {
        when(() => repo.addExpense(
              amount: any(named: 'amount'),
              categoryId: any(named: 'categoryId'),
              date: any(named: 'date'),
              isManual: any(named: 'isManual'),
              note: any(named: 'note'),
              receiptId: any(named: 'receiptId'),
              isRecurring: any(named: 'isRecurring'),
              recurringPeriod: any(named: 'recurringPeriod'),
              tags: any(named: 'tags'),
            )).thenAnswer(
          (_) async =>
              const Left<Failure, int>(CacheFailure(message: 'boom')),
        );
        return build();
      },
      act: (AddExpenseBloc b) async {
        b.add(const AddExpenseStarted());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        b
          ..add(const AddExpenseAmountChanged(input: '10,00'))
          ..add(const AddExpenseSubmitted());
      },
      verify: (AddExpenseBloc b) {
        expect(b.state, isA<AddExpenseReady>());
        expect((b.state as AddExpenseReady).isSubmitting, isFalse);
      },
    );
  });
}
