import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';

import '../../../helpers/test_database.dart';

/// The local copy of the server's published deadline corrections.
///
/// 🚨 The property under test throughout is that a pull REPLACES rather than
/// merges. That is the only mechanism by which a withdrawn correction is
/// withdrawn: the publisher retracts an extension by deleting its row, and a
/// merge would leave every device applying a correction the tax authority has
/// taken back — with no way to reach it. See D-17.
void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  TaxCalendarOverridesCompanion row({
    String remoteId = 'ovr-1',
    String market = 'TR',
    String kind = 'kdv1',
    int month = 8,
    int installmentIndex = 0,
    DateTime? declarationDueDate,
    String reason = 'VUK Sirküleri No: 175',
  }) =>
      TaxCalendarOverridesCompanion.insert(
        remoteId: remoteId,
        market: market,
        kind: kind,
        periodStart: DateTime.utc(2026, month),
        installmentIndex: Value<int>(installmentIndex),
        declarationDueDate: Value<DateTime?>(
          declarationDueDate ?? DateTime.utc(2026, 9, 30),
        ),
        reason: reason,
        fetchedAt: DateTime.utc(2026, 9, 15, 10),
      );

  group('replaceMarket', () {
    test('should store what a pull returned', () async {
      await db.taxCalendarOverrideDao.replaceMarket(
        'TR',
        <TaxCalendarOverridesCompanion>[
          row(),
          row(remoteId: 'ovr-2', month: 9),
        ],
      );

      expect(await db.taxCalendarOverrideDao.getForMarket('TR'), hasLength(2));
    });

    test('should drop a correction the server no longer returns', () async {
      await db.taxCalendarOverrideDao.replaceMarket(
        'TR',
        <TaxCalendarOverridesCompanion>[
          row(),
          row(remoteId: 'ovr-2', month: 9),
        ],
      );

      // The publisher deleted the second row. A merge would keep applying it.
      await db.taxCalendarOverrideDao.replaceMarket(
        'TR',
        <TaxCalendarOverridesCompanion>[row()],
      );

      final List<TaxCalendarOverride> stored =
          await db.taxCalendarOverrideDao.getForMarket('TR');
      expect(stored, hasLength(1));
      expect(stored.single.remoteId, 'ovr-1');
    });

    test('should apply an empty response as written', () async {
      await db.taxCalendarOverrideDao.replaceMarket(
        'TR',
        <TaxCalendarOverridesCompanion>[row()],
      );

      // "Every correction has been withdrawn" is a thing the server is allowed
      // to say, and the client has to be able to hear it.
      await db.taxCalendarOverrideDao
          .replaceMarket('TR', <TaxCalendarOverridesCompanion>[]);

      expect(await db.taxCalendarOverrideDao.getForMarket('TR'), isEmpty);
    });

    test('should not touch another market on the strength of this one',
        () async {
      await db.taxCalendarOverrideDao.replaceMarket(
        'DE',
        <TaxCalendarOverridesCompanion>[row(remoteId: 'de-1', market: 'DE')],
      );

      // A TR pull says nothing whatsoever about DE's calendar.
      await db.taxCalendarOverrideDao
          .replaceMarket('TR', <TaxCalendarOverridesCompanion>[]);

      expect(await db.taxCalendarOverrideDao.getForMarket('DE'), hasLength(1));
    });

    test('should re-emit to a watcher when a pull lands', () async {
      // The calendar screen watches this table, so a pull that landed
      // mid-session has to reach it without the puller knowing who is looking.
      final List<int> seen = <int>[];
      final StreamSubscription<List<TaxCalendarOverride>> sub = db
          .taxCalendarOverrideDao
          .watchAll()
          .listen((List<TaxCalendarOverride> rows) => seen.add(rows.length));
      await pumpEventQueue();

      await db.taxCalendarOverrideDao.replaceMarket(
        'TR',
        <TaxCalendarOverridesCompanion>[row()],
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, containsAllInOrder(<int>[0, 1]));
    });
  });

  test('sign-out should leave the published corrections in place', () async {
    await db.taxCalendarOverrideDao.replaceMarket(
      'TR',
      <TaxCalendarOverridesCompanion>[row()],
    );

    // They are not the user's data — a filing extension is published
    // regulatory fact, identical for everyone — and dropping them would leave
    // the next account on stale catalog dates until its first pull, for no
    // privacy gain.
    await db.clearUserData();

    expect(await db.taxCalendarOverrideDao.getAll(), hasLength(1));
  });
}
