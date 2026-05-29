import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';

/// Loads the stored [UserPreferences], falling back to defaults.
class GetPreferencesUseCase implements UseCase<UserPreferences, NoParams> {
  const GetPreferencesUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, UserPreferences>> call(NoParams params) {
    return _repository.getPreferences();
  }
}
