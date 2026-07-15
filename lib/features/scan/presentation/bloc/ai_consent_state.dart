part of 'ai_consent_cubit.dart';

sealed class AiConsentState extends Equatable {
  const AiConsentState();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Stored preference not read yet.
final class AiConsentLoading extends AiConsentState {
  const AiConsentLoading();
}

/// Stored preference resolved — [status] drives whether the scan flow must
/// still ask.
final class AiConsentReady extends AiConsentState {
  const AiConsentReady({required this.status});

  final AiConsentStatus status;

  @override
  List<Object?> get props => <Object?>[status];
}
