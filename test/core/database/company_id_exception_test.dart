import 'package:drift/drift.dart' show GeneratedColumn, TableInfo;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

import '../../helpers/test_database.dart';

/// The `company_id` exception, and the test that closes it.
///
/// CLAUDE.md is unambiguous: "personal = companyId null" is forbidden, because
/// personal is a company row like any other and code that assumes otherwise
/// breaks the moment a second space exists. 1.3.0 takes a stated, temporary
/// exception to that rule — the three tables this release adds carry
/// `company_id` so the 1.4.0 backfill has somewhere to write, but the value is
/// NULL everywhere and RLS scopes on `user_id` instead.
///
/// A temporary exception with no expiry is a permanent one. This file is the
/// expiry. Two halves:
///
///   * The live group pins today's state exactly as documented — the column
///     exists on all three tables and every row has it NULL. It fails the day
///     someone starts writing company ids without doing the rest of the work,
///     and it fails again in 1.4.0 when the backfill legitimately lands, which
///     is the point at which whoever is doing that work is forced to read the
///     other half.
///   * The skipped group is that other half: the invariant 1.4.0 has to
///     satisfy. It is enabled by deleting the `skip` argument, and it must go
///     green before the exception can be called closed.
///
/// Written during Block 4 rather than Block 3 because it now covers all three
/// tables at once — `product_event_counters` from Block 3, plus the two the
/// tax calendar adds — instead of being written once and widened twice.
void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  List<String> columnsOf(TableInfo<dynamic, dynamic> table) => table.$columns
      .map((GeneratedColumn<Object> c) => c.name)
      .toList();

  /// Writes one row into each of the three tables through the normal paths.
  Future<void> seedOneOfEach() async {
    await db.productEventDao.increment(
      eventKey: 'scan_started',
      day: '2026-09-01',
    );
    await db.taxProfileDao.save(
      const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
    );
    await db.taxObligationDao.upsertGenerated(
      generationKey: 'kdv1|2026-08-01|0',
      kind: 'kdv1',
      periodKind: 'monthly',
      periodStart: DateTime.utc(2026, 8),
      periodEnd: DateTime.utc(2026, 8, 31),
    );
  }

  group('the 1.3.0 exception, as documented', () {
    test('should carry company_id on all three of the new tables', () {
      // Carried but unused. Without the column, 1.4.0's backfill would be a
      // schema migration on live rows instead of an UPDATE.
      expect(columnsOf(db.productEventCounters), contains('company_id'));
      expect(columnsOf(db.taxProfiles), contains('company_id'));
      expect(columnsOf(db.taxObligations), contains('company_id'));
    });

    test('should leave company_id null on every row it writes', () async {
      await seedOneOfEach();

      expect(
        (await db.select(db.productEventCounters).get())
            .map((ProductEventCounter r) => r.companyId),
        everyElement(isNull),
      );
      expect(
        (await db.select(db.taxProfiles).get())
            .map((TaxProfile r) => r.companyId),
        everyElement(isNull),
      );
      expect(
        (await db.select(db.taxObligations).get())
            .map((TaxObligation r) => r.companyId),
        everyElement(isNull),
      );
    });
  });

  group('the invariant 1.4.0 has to satisfy', () {
    test('should give every synced row a company id', () async {
      // Enable this by deleting the `skip:` below, once 1.4.0's migration has
      // created the personal company and backfilled these three tables. When
      // it passes, the exception above is closed and the live group's
      // "everything is null" expectation is the thing that has to be deleted.
      await seedOneOfEach();

      expect(
        (await db.select(db.productEventCounters).get())
            .map((ProductEventCounter r) => r.companyId),
        everyElement(isNotNull),
      );
      expect(
        (await db.select(db.taxProfiles).get())
            .map((TaxProfile r) => r.companyId),
        everyElement(isNotNull),
      );
      expect(
        (await db.select(db.taxObligations).get())
            .map((TaxObligation r) => r.companyId),
        everyElement(isNotNull),
      );
    },
        skip: '1.4.0 — company_id is NULL by design in 1.3.0 under the stated '
            'exception in CLAUDE.md. Enable this with the 1.4.0 backfill '
            'migration; it is the test that closes the exception.');

    test('should never let personal mean "company id is null"', () async {
      // The rule the exception suspends. A personal space is a company row
      // like any other, so once 1.4.0 lands there is no such thing as a row
      // whose null company id means "personal" — and any code that reads it
      // that way is a bug this assertion catches.
      await seedOneOfEach();

      final List<TaxProfile> profiles = await db.select(db.taxProfiles).get();
      expect(profiles, isNotEmpty);
      for (final TaxProfile profile in profiles) {
        expect(
          profile.companyId,
          isNotNull,
          reason: 'a personal space is a company row, not a null',
        );
      }
    },
        skip: '1.4.0 — see above. Same switch, same migration.');
  });
}
