import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/scan/presentation/bloc/ai_consent_cubit.dart';
import 'package:smartspend/features/settings/domain/entities/ai_consent_status.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_ai_consent.dart';

class _MockGetPreferences extends Mock implements GetPreferencesUseCase {}

class _MockSetAiConsent extends Mock implements SetAiConsentUseCase {}

void main() {
  late _MockGetPreferences getPreferences;
  late _MockSetAiConsent setAiConsent;

  setUpAll(() {
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    getPreferences = _MockGetPreferences();
    setAiConsent = _MockSetAiConsent();
  });

  AiConsentCubit build() => AiConsentCubit(
    getPreferences: getPreferences,
    setAiConsent: setAiConsent,
  );

  void mockStored(AiConsentStatus status) {
    when(() => getPreferences(any())).thenAnswer(
      (_) async => Right<Failure, UserPreferences>(
        UserPreferences.defaults.copyWith(aiConsent: status),
      ),
    );
  }

  group('ensureLoaded', () {
    blocTest<AiConsentCubit, AiConsentState>(
      'should emit [ready] with the stored status',
      build: () {
        mockStored(AiConsentStatus.granted);
        return build();
      },
      act: (AiConsentCubit c) => c.ensureLoaded(),
      expect: () => <AiConsentState>[
        const AiConsentReady(status: AiConsentStatus.granted),
      ],
    );

    blocTest<AiConsentCubit, AiConsentState>(
      'should resolve to notAsked when the preference is unreadable',
      build: () {
        when(() => getPreferences(any())).thenAnswer(
          (_) async => const Left<Failure, UserPreferences>(
            CacheFailure(message: 'boom'),
          ),
        );
        return build();
      },
      act: (AiConsentCubit c) => c.ensureLoaded(),
      expect: () => <AiConsentState>[
        const AiConsentReady(status: AiConsentStatus.notAsked),
      ],
    );

    test('should not re-read once resolved', () async {
      mockStored(AiConsentStatus.denied);
      final AiConsentCubit cubit = build();

      final AiConsentStatus first = await cubit.ensureLoaded();
      final AiConsentStatus second = await cubit.ensureLoaded();

      expect(first, AiConsentStatus.denied);
      expect(second, AiConsentStatus.denied);
      verify(() => getPreferences(any())).called(1);
      await cubit.close();
    });
  });

  group('decide', () {
    blocTest<AiConsentCubit, AiConsentState>(
      'should emit granted and persist the grant',
      build: () {
        when(
          () => setAiConsent(any()),
        ).thenAnswer((_) async => const Right<Failure, Unit>(unit));
        return build();
      },
      act: (AiConsentCubit c) => c.decide(granted: true),
      expect: () => <AiConsentState>[
        const AiConsentReady(status: AiConsentStatus.granted),
      ],
      verify: (_) => verify(() => setAiConsent(true)).called(1),
    );

    blocTest<AiConsentCubit, AiConsentState>(
      'should emit denied and persist the denial',
      build: () {
        when(
          () => setAiConsent(any()),
        ).thenAnswer((_) async => const Right<Failure, Unit>(unit));
        return build();
      },
      act: (AiConsentCubit c) => c.decide(granted: false),
      expect: () => <AiConsentState>[
        const AiConsentReady(status: AiConsentStatus.denied),
      ],
      verify: (_) => verify(() => setAiConsent(false)).called(1),
    );
  });
}
