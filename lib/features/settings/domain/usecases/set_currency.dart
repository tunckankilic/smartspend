import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';

/// Persists the user's default currency (one of `kSupportedCurrencies`).
class SetCurrencyUseCase implements UseCase<Unit, String> {
  const SetCurrencyUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String currencyCode) {
    return _repository.setCurrency(currencyCode);
  }
}
