import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';

/// Toggles the user's notification opt-in preference.
class SetNotificationsEnabledUseCase implements UseCase<Unit, bool> {
  const SetNotificationsEnabledUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(bool enabled) {
    return _repository.setNotificationsEnabled(enabled);
  }
}
