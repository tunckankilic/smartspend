import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  group('UserSettingsDao', () {
    test('getValue should be null for an unset key', () async {
      expect(await db.userSettingsDao.getValue('currency'), isNull);
    });

    test('setValue should persist and getValue read it back', () async {
      await db.userSettingsDao.setValue('currency', 'EUR');
      expect(await db.userSettingsDao.getValue('currency'), 'EUR');
    });

    test('setValue should upsert on a repeated key', () async {
      await db.userSettingsDao.setValue('locale', 'tr');
      await db.userSettingsDao.setValue('locale', 'de');
      expect(await db.userSettingsDao.getValue('locale'), 'de');
    });
  });
}
