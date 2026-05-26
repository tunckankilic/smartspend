import 'package:drift/native.dart';

import 'package:smartspend/core/database/app_database.dart';

/// Builds a fresh in-memory [AppDatabase] for tests. Migration `onCreate` runs
/// so the 15 default categories are seeded just like on a real device first
/// launch — tests that exercise category lookups can rely on them.
AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}
