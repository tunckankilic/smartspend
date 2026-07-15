// ignore_for_file: prefer_initializing_formals — private field convention.

import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/entities/ai_consent_status.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_ai_consent.dart';

part 'ai_consent_state.dart';

/// Gatekeeper for the App Store 5.1.2(i) consent ask on the Scan tab.
///
/// Before the first capture the page calls [ensureLoaded]; when the answer
/// is [AiConsentStatus.notAsked] it shows the consent dialog and records the
/// choice via [decide]. Enforcement does NOT live here — the scan repository
/// re-reads the stored preference before every cloud OCR call and fails
/// closed — so this cubit is pure ask-once UX.
class AiConsentCubit extends Cubit<AiConsentState> {
  AiConsentCubit({
    required GetPreferencesUseCase getPreferences,
    required SetAiConsentUseCase setAiConsent,
  }) : _getPreferences = getPreferences,
       _setAiConsent = setAiConsent,
       super(const AiConsentLoading());

  final GetPreferencesUseCase _getPreferences;
  final SetAiConsentUseCase _setAiConsent;

  /// Resolves the stored consent, loading it on first use. An unreadable
  /// preference resolves to [AiConsentStatus.notAsked] so the user simply
  /// gets asked (again) — never silently granted.
  Future<AiConsentStatus> ensureLoaded() async {
    final AiConsentState current = state;
    if (current is AiConsentReady) return current.status;
    final Either<Failure, UserPreferences> result = await _getPreferences(
      const NoParams(),
    );
    final AiConsentStatus status = result.fold(
      (Failure _) => AiConsentStatus.notAsked,
      (UserPreferences p) => p.aiConsent,
    );
    emit(AiConsentReady(status: status));
    return status;
  }

  /// Persists the dialog answer. The UI reflects the choice immediately;
  /// if the write failed the stored value stays `notAsked`, so the scan
  /// repository still refuses cloud calls and the dialog re-appears next
  /// session — failing closed on both ends.
  Future<void> decide({required bool granted}) async {
    emit(
      AiConsentReady(
        status: granted ? AiConsentStatus.granted : AiConsentStatus.denied,
      ),
    );
    await _setAiConsent(granted);
  }
}
