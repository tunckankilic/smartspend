import 'package:drift/drift.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/tables.dart';

part 'user_settings_dao.g.dart';

/// Generic key/value accessor for the device-local [UserSettings] table.
///
/// Holds cross-cutting preferences (default currency, notification opt-in)
/// that the cloud `user_settings` row mirrors. The sync watermark uses its
/// own [SyncDao] helpers; this DAO is for user-facing preference keys.
@DriftAccessor(tables: <Type>[UserSettings])
class UserSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$UserSettingsDaoMixin {
  UserSettingsDao(super.db);

  /// Reads the raw string for [key], or `null` if unset.
  Future<String?> getValue(String key) async {
    final UserSetting? row =
        await (select(userSettings)
              ..where(($UserSettingsTable t) => t.key.equals(key))
              ..limit(1))
            .getSingleOrNull();
    return row?.value;
  }

  /// Upserts [value] under [key], stamping `updated_at`.
  Future<void> setValue(String key, String value) {
    return into(userSettings).insertOnConflictUpdate(
      UserSettingsCompanion.insert(
        key: key,
        value: value,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }
}
