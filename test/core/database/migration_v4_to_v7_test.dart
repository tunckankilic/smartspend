import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

/// Migration coverage for schema v4 → v7 — the whole of 1.3.0's schema work.
///
/// v4 is not an arbitrary starting point: every published SmartSpend (1.0.0,
/// 1.0.1, 1.1.0, 1.2.0, 1.2.1) ships schema v4, because the v1→v4 steps all
/// landed during Sprints 6/7/9 before the first App Store release. A user who
/// skips releases and jumps straight from 1.0.0 to 1.3.0 therefore takes the
/// exact same upgrade path as one coming from 1.2.1 — the one this file
/// exercises.
///
/// There is deliberately no snapshot for v5, v6 or v7, and no test starting
/// from any of them. Those versions exist only between commits on this branch
/// and were never published, so no device can ever upgrade *from* one;
/// CLAUDE.md's rule is that snapshots are taken per **published** schema
/// version, not per version. Writing one would create a fixture for a path
/// that cannot occur and imply the version is frozen when it is still free to
/// change until 1.3.0 ships — which is exactly what Block 4 did to v7, adding
/// its tables to a version Block 3 had already introduced.
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
  /// ask it for an old schema directly. Instead we let it create the current
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

    // Strip comments line by line *before* splitting on `;`. Splitting first
    // and then discarding chunks that start with `--` silently swallows the
    // statement that follows the header block, because the header holds no
    // semicolon of its own and rides along with it.
    final String snapshot =
        await File('test/core/database/schemas/v4.sql').readAsString();
    final String ddl = snapshot
        .split('\n')
        .where((String line) => !line.trimLeft().startsWith('--'))
        .join('\n');
    for (final String statement in ddl.split(';')) {
      final String sql = statement.trim();
      if (sql.isEmpty) continue;
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

  test('the v4 fixture replays the whole snapshot, not part of it', () async {
    // Guards the fixture itself: an earlier version of `buildV4Database`
    // split the file on `;` first, which made the header comment swallow the
    // first CREATE TABLE. The migration tests still passed, because none of
    // them happened to touch that table.
    final String snapshot =
        await File('test/core/database/schemas/v4.sql').readAsString();
    final Iterable<String> declared = RegExp(
      r'CREATE (?:TABLE|INDEX) "?(\w+)"?',
    ).allMatches(snapshot).map((RegExpMatch m) => m.group(1)!);
    expect(declared, contains('budget_alerts'));

    await buildV4Database();
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);
    final Set<String> live = await tableNames(db);
    final Iterable<String> tables =
        declared.where((String n) => !n.startsWith('idx_'));
    for (final String name in tables) {
      expect(live, contains(name), reason: '$name missing from the fixture');
    }
  });

  test('upgrading a v4 database creates every 1.3.0 table', () async {
    await buildV4Database();

    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    // One open, three migration steps (4 → 5 → 6 → 7). A device coming from
    // any published release runs all of them in a single upgrade, which is
    // exactly the path a user who skipped 1.2.x takes.
    expect(
      await tableNames(db),
      containsAll(<String>[
        'sync_conflict_payloads',
        'sync_deferred_rows',
        'product_event_counters',
        'tax_profiles',
        'tax_obligations',
      ]),
    );
    expect(await userVersion(db), 7);
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

  test('the migrated telemetry table counts, not merely exists', () async {
    await buildV4Database();
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    // Two increments on one key must land on one row summing to 2. If the
    // unique key had not survived the migration the second call would insert
    // a second row instead, and every counter this release reports would be
    // split across duplicates — a failure that a mere `has_table` check would
    // sail straight past.
    await db.productEventDao.increment(
      eventKey: 'scan_started',
      day: '2026-09-01',
    );
    await db.productEventDao.increment(
      eventKey: 'scan_started',
      day: '2026-09-01',
    );

    final ProductEventCounter? row = await db.productEventDao.find(
      eventKey: 'scan_started',
      day: '2026-09-01',
    );
    expect(row, isA<ProductEventCounter>());
    expect(row!.count, 2);
    expect(await db.productEventDao.getAll(), hasLength(1));
  });

  test('the migrated profile table stores answers, not merely exists',
      () async {
    await buildV4Database();

    final AppDatabase db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    // A migrated table with the wrong defaults would hand the generator a
    // profile full of "no" instead of "not asked" — which drops obligations
    // the user never declined.
    await db.taxProfileDao.save(
      const TaxpayerProfile(
        legalForm: TaxpayerLegalForm.limited,
        employsStaff: TaxpayerAnswer.yes,
      ),
    );

    final TaxpayerProfile stored = await db.taxProfileDao.getProfile();
    expect(stored.legalForm, TaxpayerLegalForm.limited);
    expect(stored.employsStaff, TaxpayerAnswer.yes);
    expect(stored.ownsVehicle, TaxpayerAnswer.unknown);
    expect(stored.bagkurInsured, TaxpayerAnswer.unknown);
  });

  test('the upgrade path and a fresh install agree on the whole schema',
      () async {
    // A migration that builds subtly different tables than `createAll` is a
    // classic way for two users on the same version to diverge — and it only
    // shows up for the half of them who upgraded. Compare every object SQLite
    // itself reports, not just the tables this release happened to add.
    Future<Map<String, String>> schemaOf(AppDatabase db) async {
      final List<QueryRow> rows = await db
          .customSelect(
            'SELECT name, sql FROM sqlite_master '
            "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
            'ORDER BY name;',
          )
          .get();
      return <String, String>{
        for (final QueryRow r in rows)
          r.read<String>('name'): r.read<String>('sql'),
      };
    }

    await buildV4Database();
    final AppDatabase migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
    final Map<String, String> migratedSchema = await schemaOf(migrated);
    // Closed before the second database opens: two live AppDatabase
    // instances make Drift (rightly) warn about racing executors, and a
    // noisy test log trains you to ignore the warning that matters.
    await migrated.close();

    final AppDatabase fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    final Map<String, String> freshSchema = await schemaOf(fresh);

    expect(migratedSchema.keys, freshSchema.keys);
    expect(migratedSchema, freshSchema);
  });
}
