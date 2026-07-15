import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';

/// Persists the user's decision on sending receipt photos to the
/// third-party AI service (Google Gemini) — `true` grants, `false` denies.
class SetAiConsentUseCase implements UseCase<Unit, bool> {
  const SetAiConsentUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(bool granted) {
    return _repository.setAiConsent(granted);
  }
}
