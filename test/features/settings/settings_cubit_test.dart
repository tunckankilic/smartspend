import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/entities/ai_consent_status.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_ai_consent.dart';
import 'package:smartspend/features/settings/domain/usecases/set_currency.dart';
import 'package:smartspend/features/settings/domain/usecases/set_notifications_enabled.dart';
import 'package:smartspend/features/settings/presentation/bloc/settings_cubit.dart';

class _MockGetPreferences extends Mock implements GetPreferencesUseCase {}

class _MockSetCurrency extends Mock implements SetCurrencyUseCase {}

class _MockSetNotifications extends Mock
    implements SetNotificationsEnabledUseCase {}

class _MockSetAiConsent extends Mock implements SetAiConsentUseCase {}

void main() {
  late _MockGetPreferences getPreferences;
  late _MockSetCurrency setCurrency;
  late _MockSetNotifications setNotifications;
  late _MockSetAiConsent setAiConsent;

  const UserPreferences loaded = UserPreferences(
    currencyCode: 'EUR',
    notificationsEnabled: true,
  );

  setUpAll(() {
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    getPreferences = _MockGetPreferences();
    setCurrency = _MockSetCurrency();
    setNotifications = _MockSetNotifications();
    setAiConsent = _MockSetAiConsent();
  });

  SettingsCubit build() => SettingsCubit(
    getPreferences: getPreferences,
    setCurrency: setCurrency,
    setNotifications: setNotifications,
    setAiConsentUseCase: setAiConsent,
  );

  group('load', () {
    blocTest<SettingsCubit, SettingsState>(
      'should emit [loading, ready] with stored prefs on success',
      build: () {
        when(() => getPreferences(any())).thenAnswer(
          (_) async => const Right<Failure, UserPreferences>(loaded),
        );
        return build();
      },
      act: (SettingsCubit c) => c.load(),
      expect: () => <SettingsState>[
        const SettingsState(status: SettingsStatus.loading),
        const SettingsState(
          status: SettingsStatus.ready,
          preferences: loaded,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'should emit [loading, failure] when load fails',
      build: () {
        when(() => getPreferences(any())).thenAnswer(
          (_) async => const Left<Failure, UserPreferences>(
            CacheFailure(message: 'boom'),
          ),
        );
        return build();
      },
      act: (SettingsCubit c) => c.load(),
      expect: () => <SettingsState>[
        const SettingsState(status: SettingsStatus.loading),
        const SettingsState(
          status: SettingsStatus.failure,
          failure: CacheFailure(message: 'boom'),
        ),
      ],
    );
  });

  group('changeCurrency', () {
    blocTest<SettingsCubit, SettingsState>(
      'should optimistically apply the new currency and keep it on success',
      build: () {
        when(
          () => setCurrency(any()),
        ).thenAnswer((_) async => const Right<Failure, Unit>(unit));
        return build();
      },
      act: (SettingsCubit c) => c.changeCurrency('USD'),
      expect: () => <SettingsState>[
        SettingsState(
          preferences: UserPreferences.defaults.copyWith(currencyCode: 'USD'),
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'should roll back to the previous currency on failure',
      build: () {
        when(() => setCurrency(any())).thenAnswer(
          (_) async => const Left<Failure, Unit>(CacheFailure(message: 'nope')),
        );
        return build();
      },
      act: (SettingsCubit c) => c.changeCurrency('USD'),
      expect: () => <SettingsState>[
        SettingsState(
          preferences: UserPreferences.defaults.copyWith(currencyCode: 'USD'),
        ),
        const SettingsState(
          status: SettingsStatus.failure,
          failure: CacheFailure(message: 'nope'),
          preferences: UserPreferences.defaults,
        ),
      ],
    );
  });

  group('toggleNotifications', () {
    blocTest<SettingsCubit, SettingsState>(
      'should roll back the toggle on failure',
      build: () {
        when(() => setNotifications(any())).thenAnswer(
          (_) async => const Left<Failure, Unit>(CacheFailure(message: 'x')),
        );
        return build();
      },
      act: (SettingsCubit c) => c.toggleNotifications(false),
      expect: () => <SettingsState>[
        SettingsState(
          preferences: UserPreferences.defaults.copyWith(
            notificationsEnabled: false,
          ),
        ),
        const SettingsState(
          status: SettingsStatus.failure,
          failure: CacheFailure(message: 'x'),
          preferences: UserPreferences.defaults,
        ),
      ],
    );
  });

  group('setAiConsent', () {
    blocTest<SettingsCubit, SettingsState>(
      'should optimistically grant AI consent and keep it on success',
      build: () {
        when(
          () => setAiConsent(any()),
        ).thenAnswer((_) async => const Right<Failure, Unit>(unit));
        return build();
      },
      act: (SettingsCubit c) => c.setAiConsent(granted: true),
      expect: () => <SettingsState>[
        SettingsState(
          preferences: UserPreferences.defaults.copyWith(
            aiConsent: AiConsentStatus.granted,
          ),
        ),
      ],
      verify: (_) => verify(() => setAiConsent(true)).called(1),
    );

    blocTest<SettingsCubit, SettingsState>(
      'should persist a denial as an explicit choice',
      build: () {
        when(
          () => setAiConsent(any()),
        ).thenAnswer((_) async => const Right<Failure, Unit>(unit));
        return build();
      },
      act: (SettingsCubit c) => c.setAiConsent(granted: false),
      expect: () => <SettingsState>[
        SettingsState(
          preferences: UserPreferences.defaults.copyWith(
            aiConsent: AiConsentStatus.denied,
          ),
        ),
      ],
      verify: (_) => verify(() => setAiConsent(false)).called(1),
    );

    blocTest<SettingsCubit, SettingsState>(
      'should roll back the consent toggle on failure',
      build: () {
        when(() => setAiConsent(any())).thenAnswer(
          (_) async => const Left<Failure, Unit>(CacheFailure(message: 'x')),
        );
        return build();
      },
      act: (SettingsCubit c) => c.setAiConsent(granted: true),
      expect: () => <SettingsState>[
        SettingsState(
          preferences: UserPreferences.defaults.copyWith(
            aiConsent: AiConsentStatus.granted,
          ),
        ),
        const SettingsState(
          status: SettingsStatus.failure,
          failure: CacheFailure(message: 'x'),
          preferences: UserPreferences.defaults,
        ),
      ],
    );
  });
}
