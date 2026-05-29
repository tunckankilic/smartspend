import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/repositories/export_repository.dart';
import 'package:smartspend/features/settings/domain/repositories/settings_repository.dart';
import 'package:smartspend/features/settings/domain/usecases/export_data.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_currency.dart';
import 'package:smartspend/features/settings/domain/usecases/set_notifications_enabled.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockExportRepository extends Mock implements ExportRepository {}

void main() {
  late _MockSettingsRepository settings;
  late _MockExportRepository export;

  setUp(() {
    settings = _MockSettingsRepository();
    export = _MockExportRepository();
  });

  group('GetPreferencesUseCase', () {
    test('should return the stored preferences', () async {
      when(settings.getPreferences).thenAnswer(
        (_) async => const Right<Failure, UserPreferences>(
          UserPreferences.defaults,
        ),
      );

      final Either<Failure, UserPreferences> result =
          await GetPreferencesUseCase(settings)(const NoParams());

      expect(
        result,
        const Right<Failure, UserPreferences>(UserPreferences.defaults),
      );
      verify(settings.getPreferences).called(1);
    });
  });

  group('SetCurrencyUseCase', () {
    test('should forward the currency code', () async {
      when(() => settings.setCurrency('EUR'))
          .thenAnswer((_) async => const Right<Failure, Unit>(unit));

      final Either<Failure, Unit> result =
          await SetCurrencyUseCase(settings)('EUR');

      expect(result, const Right<Failure, Unit>(unit));
      verify(() => settings.setCurrency('EUR')).called(1);
    });
  });

  group('SetNotificationsEnabledUseCase', () {
    test('should forward the toggle value', () async {
      when(() => settings.setNotificationsEnabled(false))
          .thenAnswer((_) async => const Right<Failure, Unit>(unit));

      final Either<Failure, Unit> result =
          await SetNotificationsEnabledUseCase(settings)(false);

      expect(result, const Right<Failure, Unit>(unit));
      verify(() => settings.setNotificationsEnabled(false)).called(1);
    });
  });

  group('ExportDataUseCase', () {
    test('should forward the date bounds to the repository', () async {
      final DateTime from = DateTime.utc(2026);
      final DateTime to = DateTime.utc(2026, 6);
      final ExportResult expected = ExportResult(
        url: 'https://example.test/export.csv',
        expiresAt: DateTime.utc(2026, 6, 2),
        rowCount: 42,
      );
      when(() => export.exportExpenses(from: from, to: to))
          .thenAnswer((_) async => Right<Failure, ExportResult>(expected));

      final Either<Failure, ExportResult> result =
          await ExportDataUseCase(export)(ExportParams(from: from, to: to));

      expect(result, Right<Failure, ExportResult>(expected));
      verify(() => export.exportExpenses(from: from, to: to)).called(1);
    });

    test('ExportParams props include from and to', () {
      final DateTime from = DateTime.utc(2026);
      expect(
        ExportParams(from: from),
        ExportParams(from: from),
      );
    });
  });
}
