import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/daos/user_settings_dao.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';

class _MockUserSettingsDao extends Mock implements UserSettingsDao {}

void main() {
  late _MockUserSettingsDao dao;
  late SettingsRepositoryImpl repository;

  setUp(() {
    dao = _MockUserSettingsDao();
    repository = SettingsRepositoryImpl(dao: dao);
  });

  group('getPreferences', () {
    test('should map stored values to UserPreferences', () async {
      when(() => dao.getValue('default_currency'))
          .thenAnswer((_) async => 'EUR');
      when(() => dao.getValue('notifications_enabled'))
          .thenAnswer((_) async => 'false');

      final result = await repository.getPreferences();

      expect(
        result,
        const Right<Failure, UserPreferences>(
          UserPreferences(currencyCode: 'EUR', notificationsEnabled: false),
        ),
      );
    });

    test('should fall back to defaults when nothing is stored', () async {
      when(() => dao.getValue(any())).thenAnswer((_) async => null);

      final result = await repository.getPreferences();

      expect(
        result,
        const Right<Failure, UserPreferences>(UserPreferences.defaults),
      );
    });

    test('should fall back to the app default for an invalid currency',
        () async {
      when(() => dao.getValue('default_currency'))
          .thenAnswer((_) async => 'XYZ');
      when(() => dao.getValue('notifications_enabled'))
          .thenAnswer((_) async => null);

      final result = await repository.getPreferences();

      result.fold(
        (_) => fail('expected Right'),
        (UserPreferences prefs) =>
            expect(prefs.currencyCode, UserPreferences.defaults.currencyCode),
      );
    });

    test('should return CacheFailure when the dao throws', () async {
      when(() => dao.getValue(any())).thenThrow(Exception('db'));

      final result = await repository.getPreferences();

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f, isA<CacheFailure>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('setCurrency', () {
    test('should reject an unsupported currency without writing', () async {
      final result = await repository.setCurrency('XYZ');

      expect(result.isLeft(), isTrue);
      verifyNever(() => dao.setValue(any(), any()));
    });

    test('should persist a supported currency', () async {
      when(() => dao.setValue(any(), any())).thenAnswer((_) async {});

      final result = await repository.setCurrency('USD');

      expect(result, const Right<Failure, Unit>(unit));
      verify(() => dao.setValue('default_currency', 'USD')).called(1);
    });
  });

  group('setNotificationsEnabled', () {
    test('should persist the flag as a string', () async {
      when(() => dao.setValue(any(), any())).thenAnswer((_) async {});

      final result = await repository.setNotificationsEnabled(false);

      expect(result, const Right<Failure, Unit>(unit));
      verify(() => dao.setValue('notifications_enabled', 'false')).called(1);
    });
  });
}
