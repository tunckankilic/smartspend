import 'package:drift/drift.dart' show GeneratedColumn;
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  Future<int> generateAugustVat({
    DateTime? declarationDue,
    DateTime? paymentDue,
    DateTime? now,
  }) =>
      db.taxObligationDao.upsertGenerated(
        generationKey: 'kdv1|2026-08-01|0',
        kind: 'kdv1',
        periodKind: 'monthly',
        periodStart: DateTime.utc(2026, 8),
        periodEnd: DateTime.utc(2026, 8, 31),
        declarationDueDate: declarationDue,
        paymentDueDate: paymentDue,
        now: now,
      );

  group('upsertGenerated', () {
    test('should store an item with no deadline at all', () async {
      // The normal state today: the catalog's rules are unverified, so the
      // item exists, is dated to its period, and says nothing about when it
      // is due. Showing nothing beats showing a guess.
      await generateAugustVat();

      final TaxObligation row =
          (await db.taxObligationDao.findByGenerationKey('kdv1|2026-08-01|0'))!;

      expect(row.declarationDueDate, isNull);
      expect(row.paymentDueDate, isNull);
      expect(row.amountMinor, isNull);
      expect(row.amountSource, TaxAmountSource.unknown.wireValue);
      expect(row.dueDateSource, TaxDueDateSource.catalog.wireValue);
    });

    test('should keep filing and payment dates apart', () async {
      await generateAugustVat(
        declarationDue: DateTime.utc(2026, 9, 28),
        paymentDue: DateTime.utc(2026, 9, 30),
      );

      final TaxObligation row =
          (await db.taxObligationDao.findByGenerationKey('kdv1|2026-08-01|0'))!;

      expect(row.declarationDueDate, DateTime.utc(2026, 9, 28));
      expect(row.paymentDueDate, DateTime.utc(2026, 9, 30));
    });

    test('should update the same item rather than add a second', () async {
      await generateAugustVat();
      await generateAugustVat(declarationDue: DateTime.utc(2026, 9, 28));

      final List<TaxObligation> all = await db.taxObligationDao.getAll();

      expect(all, hasLength(1));
      expect(all.single.declarationDueDate, DateTime.utc(2026, 9, 28));
    });

    test('should never clear the marks the user put on an item', () async {
      // Regeneration runs whenever the profile changes or a new period comes
      // into range. If it wiped these, it would be indistinguishable from the
      // app losing the user's data.
      final int id = await generateAugustVat();
      await db.taxObligationDao.setDeclaredAt(id, DateTime.utc(2026, 9, 20));
      await db.taxObligationDao.setPaidAt(id, DateTime.utc(2026, 9, 27));
      await db.taxObligationDao.setNote(id, 'muhasebeci onayladı');
      await db.taxObligationDao.setAmount(
        id,
        amountMinor: 125000,
        amountSource: TaxAmountSource.accountant.wireValue,
      );

      await generateAugustVat(declarationDue: DateTime.utc(2026, 9, 28));

      final TaxObligation row =
          (await db.taxObligationDao.findByGenerationKey('kdv1|2026-08-01|0'))!;
      expect(row.declaredAt, DateTime.utc(2026, 9, 20));
      expect(row.paidAt, DateTime.utc(2026, 9, 27));
      expect(row.note, 'muhasebeci onayladı');
      expect(row.amountMinor, 125000);
      expect(row.amountSource, TaxAmountSource.accountant.wireValue);
      expect(row.declarationDueDate, DateTime.utc(2026, 9, 28));
    });

    test('should not overwrite a date the user corrected', () async {
      // Their date came from their accountant. Ours is a rule nobody has
      // verified yet, so it does not get to win.
      final int id = await generateAugustVat();
      await db.taxObligationDao.setUserDueDates(
        id,
        declarationDueDate: DateTime.utc(2026, 9, 26),
      );

      await generateAugustVat(declarationDue: DateTime.utc(2026, 9, 28));

      final TaxObligation row =
          (await db.taxObligationDao.findByGenerationKey('kdv1|2026-08-01|0'))!;
      expect(row.declarationDueDate, DateTime.utc(2026, 9, 26));
      expect(row.dueDateSource, TaxDueDateSource.user.wireValue);
    });

    test('should keep a dismissal instead of regenerating over it', () async {
      final int id = await generateAugustVat();
      await db.taxObligationDao.setDismissedAt(id, DateTime.utc(2026, 9, 2));

      await generateAugustVat();

      final TaxObligation row =
          (await db.taxObligationDao.findByGenerationKey('kdv1|2026-08-01|0'))!;
      expect(row.dismissedAt, DateTime.utc(2026, 9, 2));
    });
  });

  group('marks', () {
    test('should treat filing and paying as separate acts', () async {
      final int id = await generateAugustVat();

      await db.taxObligationDao.setDeclaredAt(id, DateTime.utc(2026, 9, 20));

      final TaxObligation row = (await db.taxObligationDao.getAll()).single;
      expect(row.declaredAt, DateTime.utc(2026, 9, 20));
      expect(row.paidAt, isNull, reason: '"I filed it" is not "I paid it"');
    });

    test('should let a mark be taken back', () async {
      final int id = await generateAugustVat();
      await db.taxObligationDao.setPaidAt(id, DateTime.utc(2026, 9, 27));

      await db.taxObligationDao.setPaidAt(id, null);

      expect((await db.taxObligationDao.getAll()).single.paidAt, isNull);
    });

    test('should queue every annotation for sync', () async {
      final int id = await generateAugustVat();
      await db.syncDao.markTaxObligationSynced(id, remoteId: 'remote-1');
      expect(await db.taxObligationDao.getPendingSync(), isEmpty);

      await db.taxObligationDao.setNote(id, 'ertelendi mi?');

      final List<TaxObligation> pending =
          await db.taxObligationDao.getPendingSync();
      expect(pending, hasLength(1));
      expect(pending.single.syncStatus, SyncStatus.pendingUpdate);
    });

    test('should ignore an annotation aimed at a row that is gone', () async {
      await db.taxObligationDao.setNote(9999, 'ghost');

      expect(await db.taxObligationDao.getAll(), isEmpty);
    });
  });

  group('getDueBetween', () {
    test('should match on either deadline', () async {
      await db.taxObligationDao.upsertGenerated(
        generationKey: 'a',
        kind: 'kdv1',
        periodKind: 'monthly',
        periodStart: DateTime.utc(2026, 8),
        periodEnd: DateTime.utc(2026, 8, 31),
        declarationDueDate: DateTime.utc(2026, 9, 28),
      );
      await db.taxObligationDao.upsertGenerated(
        generationKey: 'b',
        kind: 'bagkur',
        periodKind: 'monthly',
        periodStart: DateTime.utc(2026, 8),
        periodEnd: DateTime.utc(2026, 8, 31),
        paymentDueDate: DateTime.utc(2026, 9, 30),
      );

      final List<TaxObligation> due = await db.taxObligationDao.getDueBetween(
        DateTime.utc(2026, 9),
        DateTime.utc(2026, 9, 30),
      );

      expect(due.map((TaxObligation o) => o.generationKey), <String>['a', 'b']);
    });

    test('should still show an item that has no deadline yet', () async {
      // An unverified obligation would otherwise fall out of every range and
      // vanish from the calendar entirely — the failure mode the honest
      // "no date" state exists to avoid.
      await generateAugustVat();

      final List<TaxObligation> due = await db.taxObligationDao.getDueBetween(
        DateTime.utc(2026, 8),
        DateTime.utc(2026, 8, 31),
      );

      expect(due, hasLength(1));
    });
  });

  group('user-defined items', () {
    test("should be marked as the user's own and dated by them", () async {
      await db.taxObligationDao.insertUserDefined(
        generationKey: 'custom-1',
        title: 'Kira stopajı',
        periodStart: DateTime.utc(2026, 9),
        periodEnd: DateTime.utc(2026, 9, 30),
        paymentDueDate: DateTime.utc(2026, 10, 20),
      );

      final TaxObligation row = (await db.taxObligationDao.getAll()).single;

      expect(row.isUserDefined, isTrue);
      expect(row.kind, 'custom');
      expect(row.title, 'Kira stopajı');
      expect(row.dueDateSource, TaxDueDateSource.user.wireValue);
    });
  });

  group('schema', () {
    test('should have no stored overdue column', () async {
      // 🚨 Overdue is derived from the due date and the current time. Stored,
      // it would be written by whichever device wrote last — including one
      // with a wrong clock or one that had not synced for a week — and
      // last-write-wins would hand that verdict to every other device. The
      // user would be told they missed a deadline they did not miss.
      final List<String> columns = db.taxObligations.$columns
          .map((GeneratedColumn<Object> c) => c.name.toLowerCase())
          .toList();

      expect(columns, isNot(contains('overdue')));
      expect(columns, isNot(contains('is_overdue')));
      expect(columns, contains('declaration_due_date'));
      expect(columns, contains('payment_due_date'));
    });

    test('should offer no way to record a computed amount', () async {
      // The enum has no `computed` value, so there is no call site at which
      // an app-calculated figure could be stamped as authoritative.
      expect(
        TaxAmountSource.values.map((TaxAmountSource s) => s.wireValue),
        <String>['accountant', 'user', 'unknown'],
      );
      expect(TaxAmountSource.fromWireValue('computed'),
          TaxAmountSource.unknown);
    });
  });

  group('sign-out', () {
    test('should take the generated calendar with it', () async {
      final int id = await generateAugustVat();
      await db.taxObligationDao.setNote(id, 'özel not');

      await db.clearUserData();

      expect(await db.taxObligationDao.getAll(), isEmpty);
    });
  });
}
