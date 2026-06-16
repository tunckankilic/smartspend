import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartspend/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// The Sprint 9 read-path indexes must exist on a fresh install (the
  /// `createAll` path), not only after the v3 → v4 upgrade migration.
  test('should create the Sprint 9 covering indexes on a fresh database',
      () async {
    final List<QueryRow> rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          'AND name LIKE ?',
          variables: <Variable<Object>>[const Variable<String>('idx_%')],
        )
        .get();

    final Set<String> indexNames =
        rows.map((QueryRow r) => r.read<String>('name')).toSet();

    expect(
      indexNames,
      containsAll(<String>{
        'idx_expenses_date',
        'idx_expenses_category',
        'idx_receipts_date',
      }),
    );
  });
}
