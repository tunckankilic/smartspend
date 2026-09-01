import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/database/sync_status.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() async => db.close());

  group('TaxProfileDao.getProfile', () {
    test('should answer "nothing asked yet" before the wizard is opened',
        () async {
      // Never null. "No row" and "a row with nothing answered" generate the
      // same calendar, and callers forced to tell them apart would all write
      // the same fallback — one of them wrongly.
      expect(await db.taxProfileDao.getProfile(), TaxpayerProfile.empty);
      expect(await db.taxProfileDao.getRow(), isNull);
    });

    test('should read back every answer it was given', () async {
      const TaxpayerProfile profile = TaxpayerProfile(
        legalForm: TaxpayerLegalForm.limited,
        vatLiability: VatLiability.monthly,
        withholdingLiability: WithholdingLiability.quarterly,
        employsStaff: TaxpayerAnswer.yes,
        bagkurInsured: TaxpayerAnswer.no,
        usesELedger: TaxpayerAnswer.yes,
        ownsVehicle: TaxpayerAnswer.no,
        ownsRealEstate: TaxpayerAnswer.yes,
      );

      await db.taxProfileDao.save(profile);
      final TaxpayerProfile stored = await db.taxProfileDao.getProfile();

      expect(stored.legalForm, TaxpayerLegalForm.limited);
      expect(stored.vatLiability, VatLiability.monthly);
      expect(stored.withholdingLiability, WithholdingLiability.quarterly);
      expect(stored.employsStaff, TaxpayerAnswer.yes);
      expect(stored.bagkurInsured, TaxpayerAnswer.no);
      expect(stored.usesELedger, TaxpayerAnswer.yes);
      expect(stored.ownsVehicle, TaxpayerAnswer.no);
      expect(stored.ownsRealEstate, TaxpayerAnswer.yes);
      expect(stored.isComplete, isTrue);
    });

    test('should keep a skipped question skipped', () async {
      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.sahisSirketi),
      );

      final TaxpayerProfile stored = await db.taxProfileDao.getProfile();

      // The whole point of the tri-state: an unanswered question must not
      // arrive at the generator as "no", which would silently drop every
      // obligation the user never declined.
      expect(stored.employsStaff, TaxpayerAnswer.unknown);
      expect(stored.answeredCount, 1);
      expect(stored.isComplete, isFalse);
    });

    test('should survive a value it does not recognise', () async {
      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
      );
      // What a newer client — or a 1.4.0 build with a form this one has never
      // heard of — leaves behind on a downgrade.
      await db.customStatement(
        "UPDATE tax_profiles SET legal_form = 'kooperatif';",
      );

      final TaxpayerProfile stored = await db.taxProfileDao.getProfile();

      expect(stored.legalForm, TaxpayerLegalForm.unspecified);
    });
  });

  group('TaxProfileDao.save', () {
    test('should update the single row rather than append a second', () async {
      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
      );
      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.anonim),
      );

      final List<TaxProfile> rows = await db.select(db.taxProfiles).get();

      expect(rows, hasLength(1));
      expect(rows.single.legalForm, 'anonim');
    });

    test('should queue the first save as a create', () async {
      await db.taxProfileDao.save(TaxpayerProfile.empty);

      final TaxProfile? row = await db.taxProfileDao.getRow();

      expect(row!.syncStatus, SyncStatus.pendingCreate);
      expect(await db.taxProfileDao.getPendingSync(), hasLength(1));
    });

    test('should queue a later edit as an update once the row has an id',
        () async {
      await db.taxProfileDao.save(TaxpayerProfile.empty);
      final TaxProfile created = (await db.taxProfileDao.getRow())!;
      await db.syncDao.markTaxProfileSynced(created.id, remoteId: 'remote-1');

      await db.taxProfileDao.save(
        const TaxpayerProfile(ownsVehicle: TaxpayerAnswer.yes),
      );

      expect((await db.taxProfileDao.getRow())!.syncStatus,
          SyncStatus.pendingUpdate);
    });

    test('should not erase an owner the pull already wrote', () async {
      await db.taxProfileDao.save(TaxpayerProfile.empty, userId: 'user-1');

      // A save made without a session — the settings screen before sign-in —
      // must not orphan the row from its account.
      await db.taxProfileDao.save(
        const TaxpayerProfile(usesELedger: TaxpayerAnswer.yes),
      );

      expect((await db.taxProfileDao.getRow())!.userId, 'user-1');
    });

    test('should move updatedAt forward so last-write-wins can compare',
        () async {
      await db.taxProfileDao.save(
        TaxpayerProfile.empty,
        now: DateTime.utc(2026, 9, 1, 10),
      );
      await db.taxProfileDao.save(
        const TaxpayerProfile(ownsRealEstate: TaxpayerAnswer.yes),
        now: DateTime.utc(2026, 9, 1, 12),
      );

      final TaxProfile row = (await db.taxProfileDao.getRow())!;
      expect(row.updatedAt, DateTime.utc(2026, 9, 1, 12));
      expect(row.createdAt, DateTime.utc(2026, 9, 1, 10));
    });
  });

  group('TaxProfileDao.watchProfile', () {
    test('should re-emit when an answer changes', () async {
      final Future<List<TaxpayerProfile>> collected =
          db.taxProfileDao.watchProfile().take(2).toList();

      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.serbestMeslek),
      );

      final List<TaxpayerProfile> emissions = await collected;
      expect(emissions.first, TaxpayerProfile.empty);
      expect(emissions.last.legalForm, TaxpayerLegalForm.serbestMeslek);
    });
  });

  group('sign-out', () {
    test('should take the taxpayer profile with it', () async {
      await db.taxProfileDao.save(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
        userId: 'user-1',
      );

      await db.clearUserData();

      // The most identifying row the app holds. The next account signed in on
      // this phone must not inherit a calendar built from someone else's
      // business.
      expect(await db.taxProfileDao.getRow(), isNull);
      expect(await db.taxProfileDao.getProfile(), TaxpayerProfile.empty);
    });
  });
}
