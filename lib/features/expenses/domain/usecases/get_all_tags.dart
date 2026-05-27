import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/repositories/expense_repository.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';

/// All tag names the user has previously used. Drives the autocomplete
/// suggestions in the AddExpense form's chip input.
class GetAllTagsUseCase implements UseCase<List<String>, NoParams> {
  const GetAllTagsUseCase(this._repository);

  final ExpenseRepository _repository;

  @override
  Future<Either<Failure, List<String>>> call(NoParams params) {
    return _repository.getAllTagNames();
  }
}
