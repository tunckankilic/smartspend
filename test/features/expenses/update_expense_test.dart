import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/update_expense.dart';

class _MockRepository extends Mock implements ExpenseRepository {}

void main() {
  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
  });

  group('UpdateExpenseUseCase', () {
    test('should forward every patch field to the repository', () async {
      final DateTime date = DateTime.utc(2026, 7, 7);
      when(
        () => repository.updateExpense(
          id: 10,
          amount: 4500,
          categoryId: 2,
          date: date,
          note: 'aylık',
          clearNote: false,
          isRecurring: true,
          recurringPeriod: 'monthly',
          clearRecurringPeriod: false,
          tags: const <String>['market'],
        ),
      ).thenAnswer((_) async => const Right<Failure, void>(null));

      final Either<Failure, void> result =
          await UpdateExpenseUseCase(repository)(
            UpdateExpenseParams(
              id: 10,
              amount: 4500,
              categoryId: 2,
              date: date,
              note: 'aylık',
              isRecurring: true,
              recurringPeriod: RecurringPeriod.monthly,
              tags: const <String>['market'],
            ),
          );

      expect(result.isRight(), isTrue);
      verify(
        () => repository.updateExpense(
          id: 10,
          amount: 4500,
          categoryId: 2,
          date: date,
          note: 'aylık',
          clearNote: false,
          isRecurring: true,
          recurringPeriod: 'monthly',
          clearRecurringPeriod: false,
          tags: const <String>['market'],
        ),
      ).called(1);
    });

    test('should compare params by every field', () {
      expect(
        const UpdateExpenseParams(id: 10, amount: 4500, clearNote: true),
        const UpdateExpenseParams(id: 10, amount: 4500, clearNote: true),
      );
      expect(
        const UpdateExpenseParams(id: 10, amount: 4500),
        isNot(const UpdateExpenseParams(id: 10, amount: 4600)),
      );
      expect(
        const UpdateExpenseParams(id: 10, clearRecurringPeriod: true),
        isNot(const UpdateExpenseParams(id: 10)),
      );
    });
  });
}
