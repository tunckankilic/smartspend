import 'package:smartspend/features/budget/domain/entities/budget.dart';
import 'package:smartspend/features/budget/domain/repositories/budget_repository.dart';

/// Thin wrapper around `BudgetRepository.watchActiveBudgets` so the BLoC
/// depends on a use case rather than the repository directly — keeps the
/// dependency arrow flowing toward `domain/`.
///
/// We deliberately don't wrap the stream in `Either` here: a stream
/// error is surfaced to the BLoC's `onError` handler and converted to
/// a `BudgetState` failure there.
class WatchBudgetsUseCase {
  const WatchBudgetsUseCase(this._repository);

  final BudgetRepository _repository;

  Stream<List<Budget>> call() => _repository.watchActiveBudgets();
}
