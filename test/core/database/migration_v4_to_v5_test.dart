import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';

/// Migration coverage for schema v4 → v5 (1.3.0's `sync_conflict_payloads`).
///
/// v4 is not an arbitrary starting point: every published SmartSpend (1.0.0,
/// 1.0.1, 1.1.0, 1.2.0, 1.2.1) ships schema v4, because the v1→v4 steps all
/// landed during Sprints 6/7/9 before the first App Store release. A user who
/// skips releases and jumps straight from 1.0.0 to 1.3.0 therefore takes the
/// exact same upgrade path as one coming from 1.2.1 — the one this file
/// exercises.
///
/// The v4 database is built from `schemas/v4.sql`, a captured snapshot of the
/// real shipped schema, rather than from "current code minus the new table".
/// That distinction is the point: if someone silently changes an existing v4
/// table, a snapshot-based test notices and a code-derived one cannot.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('smartspend_migration_');
    dbFile = File('${tempDir.path}/app.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Writes a genuine v4 database to [dbFile].
  ///
  /// Drift always opens at the current `schemaVersion`, so there is no way to
  /// ask it for an old schema directly. Instead we let it create the v5
  /// database, tear every table back out, replay the v4 snapshot, and stamp
  /// `user_version` back to 4. What lands on disk is a v4 database; the next
  /// open sees `from == 4` and runs the real migration.
  Future<void> buildV4Database() async {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    // Force the connection open so `onCreate` has run before we rewrite it.
    await db.customSelect('SELECT 1;').get();

    final List<QueryRow> existing = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%';",
        )
        .get();
    for (final QueryRow row in existing) {
      final String name = row.read<String>('name');
      await db.customStatement('DROP TABLE IF EXISTS "$name";');
    }

    final String snapshot =
        await File('test/core/database/schemas/v4.sql').readAsString();
    for (final String statement in snapshot.split(';')) {
      final String sql = statement.trim();
      if (sql.isEmpty || sql.startsWith('--')) continue;
      await db.customStatement('$sql;');
    }
    await db.customStatement('PRAGMA user_version = 4;');
    await db.close();
  }

  Future<int> userVersion(AppDatabase db) async {
    final List<QueryRow> rows =
        await db.customSelect('PRAGMA user_version;').get();
    return rows.first.data.values.first as int;
  }

  Future<Set<String>> tableNames(AppDatabase db) async {
    final List<QueryRow> rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%';",
        )
        .get();
    return rows.map((QueryRow r) => r.read<String>('name')).toSet();
  }

  test('upgrading a v4 database creates sync_conflict_payloads', () async {
    await buildV4Database();

    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    expect(await tableNames(db), contains('sync_conflict_payloads'));
    expect(await userVersion(db), 5);
  });

  test('upgrading a v4 database preserves the rows already in it', () async {
    await buildV4Database();

    // Seed the v4 file directly through a second connection so the data
    // predates the migration exactly as a real user's would.
    final AppDatabase seed = AppDatabase.forTesting(NativeDatabase(dbFile));
    await seed.customStatement(
      'INSERT INTO categories (id, remote_id, user_id, name, icon, color, '
      'is_custom, sort_order, updated_at, sync_status) VALUES '
      "(1, 'cat-remote', 'user-1', 'Market', 'cart', 42, 1, 3, "
      "'2026-05-01T12:00:00.000Z', 'synced');",
    );
    await seed.customStatement(
      'INSERT INTO receipts (id, remote_id, user_id, store_name, date, '
      'total, currency, created_at, updated_at, sync_status) VALUES '
      "(1, 'rcpt-remote', 'user-1', 'Migros', '2026-05-01T12:00:00.000Z', "
      "12345, 'TRY', '2026-05-01T12:00:00.000Z', "
      "'2026-05-01T12:00:00.000Z', 'synced');",
    );
    await seed.close();

    // A fresh open runs onUpgrade(4 → 5).
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    final Category category =
        (await db.syncDao.findCategoryByRemoteId('cat-remote'))!;
    expect(category.name, 'Market');
    expect(category.color, 42);
    expect(category.sortOrder, 3);
    expect(category.updatedAt.toUtc(), DateTime.utc(2026, 5, 1, 12));

    final Receipt receipt =
        (await db.syncDao.findReceiptByRemoteId('rcpt-remote'))!;
    expect(receipt.storeName, 'Migros');
    // Money stays an integer in minor units across the migration.
    expect(receipt.total, 12345);
  });

  test('the migrated conflict table is usable, not merely present', () async {
    await buildV4Database();
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    await db.syncDao.recordConflictPayload(
      tableName: 'receipts',
      remoteId: 'rcpt-remote',
      remotePayload: <String, dynamic>{'id': 'rcpt-remote', 'total': 999},
      localUpdatedAt: DateTime.utc(2026, 6),
      remoteUpdatedAt: DateTime.utc(2026, 5),
      userId: 'user-1',
    );

    final List<SyncConflictPayload> stored =
        await db.syncDao.getConflictPayloads();
    expect(stored, hasLength(1));
    expect(stored.single.remoteId, 'rcpt-remote');
  });

  test('the upgrade path and a fresh install agree on the new table', () async {
    // A migration that builds a subtly different table than `createAll` is a
    // classic way for two users on the same version to diverge. Compare the
    // DDL SQLite itself reports for each path.
    await buildV4Database();
    final AppDatabase migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
    final String migratedDdl = (await migrated
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' "
              "AND name = 'sync_conflict_payloads';",
            )
            .getSingle())
        .read<String>('sql');
    // Closed before the second database opens: two live AppDatabase
    // instances make Drift (rightly) warn about racing executors, and a
    // noisy test log trains you to ignore the warning that matters.
    await migrated.close();

    final AppDatabase fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    final String freshDdl = (await fresh
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' "
              "AND name = 'sync_conflict_payloads';",
            )
            .getSingle())
        .read<String>('sql');

    expect(migratedDdl, freshDdl);
  });
}
