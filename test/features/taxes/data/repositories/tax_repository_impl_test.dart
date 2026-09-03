import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/market_registry.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/core/services/tax_override_remote_data_source.dart';
import 'package:smartspend/features/taxes/data/repositories/tax_repository_impl.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

import '../../../../helpers/test_database.dart';


/// Stands in for the PostgREST call. The rows are whatever the test wants the
/// server to have published.
class _FakeOverrideRemote implements TaxOverrideRemoteDataSource {
  List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  Exception? failWith;
  int calls = 0;
  String? lastMarket;

  @override
  Future<List<Map<String, dynamic>>> fetchOverrides(String market) async {
    calls++;
    lastMarket = market;
    final Exception? failure = failWith;
    if (failure != null) {
      throw failure;
    }
    return rows;
  }
}

void main() {
  late AppDatabase db;
  late TaxRepository repository;

  // A fixed clock: the generated window is relative to "now", and a test that
  // moved with the wall clock would pass in September and fail in December.
  DateTime now() => DateTime.utc(2026, 9, 15, 10);

  setUp(() {
    db = createTestDatabase();
    repository = TaxRepositoryImpl(
      profileDao: db.taxProfileDao,
      obligationDao: db.taxObligationDao,
      overrideDao: db.taxCalendarOverrideDao,
      settingsDao: db.userSettingsDao,
      markets: MarketRegistry(),
      clock: now,
      random: Random(1),
    );
  });

  tearDown(() async => db.close());

  const TaxpayerProfile soleTraderWithVat = TaxpayerProfile(
    legalForm: TaxpayerLegalForm.sahisSirketi,
    vatLiability: VatLiability.monthly,
    withholdingLiability: WithholdingLiability.none,
    employsStaff: TaxpayerAnswer.no,
    bagkurInsured: TaxpayerAnswer.yes,
    usesELedger: TaxpayerAnswer.no,
    ownsVehicle: TaxpayerAnswer.no,
    ownsRealEstate: TaxpayerAnswer.no,
  );

  Future<TaxCalendarSnapshot> snapshot() =>
      repository.watchCalendar().first;

  group('profile', () {
    test('should answer empty before the wizard has ever been opened',
        () async {
      final Either<Failure, TaxpayerProfile> result =
          await repository.getProfile();

      expect(
        result.getOrElse(() => throw StateError('expected Right')),
        TaxpayerProfile.empty,
      );
    });

    test('should generate the calendar as part of saving', () async {
      // Regeneration is not a separate call the caller can forget: a profile
      // that never reaches the calendar is a form filled in for nothing.
      await repository.saveProfile(soleTraderWithVat);

      final TaxCalendarSnapshot result = await snapshot();
      expect(result.items, isNotEmpty);
      expect(result.profile, soleTraderWithVat);
    });

    test('should generate only what the profile allows', () async {
      await repository.saveProfile(soleTraderWithVat);

      final Set<TaxObligationKind> kinds = (await snapshot())
          .items
          .map((TaxCalendarItem i) => i.kind)
          .toSet();

      expect(kinds, contains(TaxObligationKind.kdv1));
      expect(kinds, contains(TaxObligationKind.bagkur));
      // Answered "no": these must not appear at all.
      expect(kinds, isNot(contains(TaxObligationKind.mphb)));
      expect(kinds, isNot(contains(TaxObligationKind.sgk4a)));
      expect(kinds, isNot(contains(TaxObligationKind.mtv)));
      expect(kinds, isNot(contains(TaxObligationKind.emlak)));
      // Wrong legal form.
      expect(kinds, isNot(contains(TaxObligationKind.kurumlar)));
    });

    test('should report what it could not generate rather than guess',
        () async {
      // A profile that says nothing about VAT frequency: the KDV items cannot
      // be placed, and the gap has to reach the screen.
      await repository.saveProfile(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
      );

      final TaxCalendarSnapshot result = await snapshot();
      expect(result.gaps, isNotEmpty);
      expect(result.isPartial, isTrue);
    });
  });

  group('generated items', () {
    setUp(() async => repository.saveProfile(soleTraderWithVat));

    test('should carry no dates while the catalog is unverified', () async {
      final TaxCalendarItem item = (await snapshot()).items.first;

      expect(item.declarationDueDate, isNull);
      expect(item.paymentDueDate, isNull);
      expect(item.hasAnyDate, isFalse);
    });

    test('should hedge every generated date', () async {
      // Two independent reasons today: the catalog rule is unverified, and no
      // year has a holiday list. Either one is enough.
      expect(
        (await snapshot())
            .items
            .every((TaxCalendarItem i) => i.needsDateWarning),
        isTrue,
      );
    });

    test('should know which steps an obligation actually has', () async {
      // Bağ-Kur is assessed, never declared. Without this the item could
      // never be completed, because declaredAt stays null forever.
      final TaxCalendarItem bagkur = (await snapshot()).items.firstWhere(
            (TaxCalendarItem i) => i.kind == TaxObligationKind.bagkur,
          );

      expect(bagkur.hasDeclarationStep, isFalse);
      expect(bagkur.hasPaymentStep, isTrue);
    });

    test('should mark KDV-2 conditional rather than assert it', () async {
      final TaxCalendarItem kdv2 = (await snapshot()).items.firstWhere(
            (TaxCalendarItem i) => i.kind == TaxObligationKind.kdv2,
          );

      expect(kdv2.isConditional, isTrue);
    });

    test('should not duplicate items when regenerated', () async {
      final int before = (await snapshot()).items.length;

      await repository.regenerate();
      await repository.regenerate();

      expect((await snapshot()).items, hasLength(before));
    });

    test("should keep the user's marks across a regeneration", () async {
      final TaxCalendarItem item = (await snapshot()).items.first;
      await repository.setPaid(item.id, DateTime.utc(2026, 9, 10));
      await repository.setNote(item.id, 'muhasebeci onayladı');

      await repository.regenerate();

      final TaxCalendarItem after = (await snapshot())
          .items
          .firstWhere((TaxCalendarItem i) => i.id == item.id);
      expect(after.paidAt, DateTime.utc(2026, 9, 10));
      expect(after.note, 'muhasebeci onayladı');
    });
  });

  group('marks and annotations', () {
    late int itemId;

    setUp(() async {
      await repository.saveProfile(soleTraderWithVat);
      itemId = (await snapshot()).items.first.id;
    });

    test('should keep filing and paying apart', () async {
      await repository.setDeclared(itemId, DateTime.utc(2026, 9, 20));

      final TaxCalendarItem item = (await repository.getItem(itemId))
          .getOrElse(() => throw StateError('expected Right'))!;
      expect(item.declaredAt, DateTime.utc(2026, 9, 20));
      expect(item.paidAt, isNull);
    });

    test('should record an amount with who said it', () async {
      await repository.setAmount(
        itemId,
        amountMinor: 125000,
        source: TaxAmountSource.accountant,
      );

      final TaxCalendarItem item = (await repository.getItem(itemId))
          .getOrElse(() => throw StateError('expected Right'))!;
      expect(item.amountMinor, 125000);
      expect(item.amountSource, TaxAmountSource.accountant);
    });

    test('should stop hedging a date the user corrected', () async {
      // Their date came from their accountant. Ours is an unverified rule, so
      // the warning belongs on ours and not on theirs.
      await repository.setUserDueDates(
        itemId,
        paymentDueDate: DateTime.utc(2026, 9, 26),
      );

      final TaxCalendarItem item = (await repository.getItem(itemId))
          .getOrElse(() => throw StateError('expected Right'))!;
      expect(item.dueDateSource, TaxDueDateSource.user);
      expect(item.needsDateWarning, isFalse);
    });

    test('should return null for an id that is not there', () async {
      final Either<Failure, TaxCalendarItem?> result =
          await repository.getItem(999999);

      expect(
        result.getOrElse(() => throw StateError('expected Right')),
        isNull,
      );
    });
  });

  group('custom items', () {
    test("should store the user's own deadline without a hedge", () async {
      await repository.addCustomItem(
        title: 'Kira stopajı',
        dueDate: DateTime.utc(2026, 10, 20),
      );

      final TaxCalendarItem item = (await snapshot()).items.single;
      expect(item.isUserDefined, isTrue);
      expect(item.title, 'Kira stopajı');
      expect(item.paymentDueDate, DateTime.utc(2026, 10, 20));
      expect(item.hasPaymentStep, isTrue);
      expect(item.hasDeclarationStep, isFalse);
      expect(
        item.needsDateWarning,
        isFalse,
        reason: 'the user is not guessing on their own behalf',
      );
    });

    test('should file a filing-type item on the filing side', () async {
      await repository.addCustomItem(
        title: 'Ek beyan',
        dueDate: DateTime.utc(2026, 10, 20),
        isPayment: false,
      );

      final TaxCalendarItem item = (await snapshot()).items.single;
      expect(item.declarationDueDate, DateTime.utc(2026, 10, 20));
      expect(item.paymentDueDate, isNull);
    });

    test('should let two identical custom items coexist', () async {
      // Same title, same date, twice. A generation key derived from those
      // would collide and silently overwrite one of them.
      await repository.addCustomItem(
        title: 'Aynı',
        dueDate: DateTime.utc(2026, 10, 20),
      );
      await repository.addCustomItem(
        title: 'Aynı',
        dueDate: DateTime.utc(2026, 10, 20),
      );

      expect((await snapshot()).items, hasLength(2));
    });

    test('should survive a regeneration untouched', () async {
      await repository.saveProfile(soleTraderWithVat);
      await repository.addCustomItem(
        title: 'Kira stopajı',
        dueDate: DateTime.utc(2026, 10, 20),
      );

      await repository.regenerate();

      expect(
        (await snapshot()).items.where((TaxCalendarItem i) => i.isUserDefined),
        hasLength(1),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Published overrides (1.3.0, Block 4, T10)
  //
  // 🚨 The regression this group exists for is the second test. An override
  // written into the calendar and merely protected from being overwritten
  // would pass the first test and fail every real user: regeneration runs on
  // every app launch, so the extension would appear to arrive and cancel
  // itself overnight. See D-17.
  // ---------------------------------------------------------------------------
  group('published overrides', () {
    late _FakeOverrideRemote remote;
    late TaxRepository repo;

    /// The KDV-1 return for August 2026 — inside the generated window for the
    /// fixed clock, and the item every test here addresses.
    const String august = '2026-08-01';
    final DateTime extended = DateTime.utc(2026, 9, 30);

    Map<String, dynamic> publishedOverride({
      String id = 'ovr-1',
      String kind = 'kdv1',
      String periodStart = august,
      int installmentIndex = 0,
      String? declarationDueDate = '2026-09-30',
      String? paymentDueDate = '2026-09-30',
      String? reason = 'VUK Sirküleri No: 175',
      String? sourceUrl,
    }) =>
        <String, dynamic>{
          'id': id,
          'market': 'TR',
          'kind': kind,
          'period_start': periodStart,
          'installment_index': installmentIndex,
          'declaration_due_date': declarationDueDate,
          'payment_due_date': paymentDueDate,
          'reason': reason,
          'source_url': sourceUrl,
        };

    Future<TaxCalendarItem> augustVat() async {
      final TaxCalendarSnapshot snap = await repo.watchCalendar().first;
      return snap.items.firstWhere(
        (TaxCalendarItem i) =>
            i.kind == TaxObligationKind.kdv1 &&
            i.periodStart == DateTime.utc(2026, 8),
      );
    }

    setUp(() async {
      remote = _FakeOverrideRemote();
      repo = TaxRepositoryImpl(
        profileDao: db.taxProfileDao,
        obligationDao: db.taxObligationDao,
        overrideDao: db.taxCalendarOverrideDao,
        settingsDao: db.userSettingsDao,
        markets: MarketRegistry(),
        overrideRemote: remote,
        clock: now,
        random: Random(1),
      );
      await repo.saveProfile(soleTraderWithVat);
    });

    test('should replace the catalog date with the published one', () async {
      // The shipped catalog has no confirmed date for this item at all, which
      // is the state the override channel exists to fix.
      expect((await augustVat()).declarationDueDate, isNull);

      remote.rows = <Map<String, dynamic>>[publishedOverride()];
      await repo.refreshOverrides(force: true);

      final TaxCalendarItem item = await augustVat();
      expect(item.declarationDueDate, extended);
      expect(item.dueDateSource, TaxDueDateSource.override);
      expect(item.dueDateOverrideReason, 'VUK Sirküleri No: 175');
    });

    test('should survive a regeneration — the launch-time overwrite', () async {
      remote.rows = <Map<String, dynamic>>[publishedOverride()];
      await repo.refreshOverrides(force: true);

      // What TaxCalendarCubit.subscribe() does on every single app launch.
      await repo.regenerate();

      final TaxCalendarItem item = await augustVat();
      expect(
        item.declarationDueDate,
        extended,
        reason: 'a regeneration must not put the catalog date back',
      );
      expect(item.dueDateSource, TaxDueDateSource.override);
    });

    test('should revert to the catalog when the override is withdrawn',
        () async {
      remote.rows = <Map<String, dynamic>>[publishedOverride()];
      await repo.refreshOverrides(force: true);
      expect((await augustVat()).dueDateSource, TaxDueDateSource.override);

      // The publisher deletes the row: the extension was cancelled, or it was
      // wrong. The client must be able to take it back.
      remote.rows = <Map<String, dynamic>>[];
      await repo.refreshOverrides(force: true);

      final TaxCalendarItem item = await augustVat();
      expect(item.dueDateSource, TaxDueDateSource.catalog);
      expect(item.declarationDueDate, isNull);
      expect(item.dueDateOverrideReason, isNull);
    });

    test('should leave a date the user entered alone', () async {
      final DateTime theirs = DateTime.utc(2026, 9, 20);
      await repo.setUserDueDates(
        (await augustVat()).id,
        declarationDueDate: theirs,
      );

      remote.rows = <Map<String, dynamic>>[publishedOverride()];
      await repo.refreshOverrides(force: true);

      // user > override > catalog. Theirs came from their accountant; ours is
      // a rule nobody has confirmed to them.
      final TaxCalendarItem item = await augustVat();
      expect(item.declarationDueDate, theirs);
      expect(item.dueDateSource, TaxDueDateSource.user);
    });

    test('should move only the deadline the override names', () async {
      // An extension routinely moves the filing date and leaves the payment
      // date where it was. A null column means "not overridden", never
      // "removed".
      remote.rows = <Map<String, dynamic>>[
        publishedOverride(paymentDueDate: null),
      ];
      await repo.refreshOverrides(force: true);

      final TaxCalendarItem item = await augustVat();
      expect(item.declarationDueDate, extended);
      expect(item.paymentDueDate, isNull);
    });

    test('should still hedge an overridden date', () async {
      remote.rows = <Map<String, dynamic>>[publishedOverride()];
      await repo.refreshOverrides(force: true);

      // An override is a date we published, not one the user's accountant
      // confirmed to them. The reason travels with it; the certainty does not.
      expect((await augustVat()).needsDateWarning, isTrue);
    });

    test('should ignore a row that states no reason', () async {
      remote.rows = <Map<String, dynamic>>[
        publishedOverride(reason: null),
        publishedOverride(id: 'ovr-2', kind: 'bagkur'),
      ];
      await repo.refreshOverrides(force: true);

      // One bad row costs its own correction and nothing else.
      expect((await augustVat()).dueDateSource, TaxDueDateSource.catalog);
      expect(await db.taxCalendarOverrideDao.getAll(), hasLength(1));
    });

    test('should ignore a row that moves neither deadline', () async {
      remote.rows = <Map<String, dynamic>>[
        publishedOverride(declarationDueDate: null, paymentDueDate: null),
      ];
      await repo.refreshOverrides(force: true);

      expect(await db.taxCalendarOverrideDao.getAll(), isEmpty);
    });

    test('should not retract everything over a response it cannot read',
        () async {
      remote.rows = <Map<String, dynamic>>[publishedOverride()];
      await repo.refreshOverrides(force: true);

      // A format change on the server must not read as "every correction has
      // been withdrawn" — that failure mode looks exactly like success.
      remote.rows = <Map<String, dynamic>>[
        <String, dynamic>{'unexpected': 'shape'},
      ];
      final Either<Failure, void> result =
          await repo.refreshOverrides(force: true);

      expect(result.isLeft(), isTrue);
      expect((await augustVat()).dueDateSource, TaxDueDateSource.override);
    });

    test('should keep the dates it had when the pull fails', () async {
      remote.rows = <Map<String, dynamic>>[publishedOverride()];
      await repo.refreshOverrides(force: true);

      remote.failWith = Exception('offline');
      final Either<Failure, void> result =
          await repo.refreshOverrides(force: true);

      expect(result.isLeft(), isTrue);
      expect((await augustVat()).declarationDueDate, extended);
    });

    test('should not pull again inside the throttle window', () async {
      await repo.refreshOverrides();
      expect(remote.calls, 1);

      // Every screen open would otherwise spend a round trip the user did not
      // ask for.
      await repo.refreshOverrides();
      expect(remote.calls, 1);

      // Pull-to-refresh is the user asking.
      await repo.refreshOverrides(force: true);
      expect(remote.calls, 2);
    });

    test('should ask only about the market whose catalog is in force',
        () async {
      await repo.refreshOverrides(force: true);
      expect(remote.lastMarket, 'TR');
    });

    test('should do nothing at all when no remote is configured', () async {
      final TaxRepository offline = TaxRepositoryImpl(
        profileDao: db.taxProfileDao,
        obligationDao: db.taxObligationDao,
        overrideDao: db.taxCalendarOverrideDao,
        settingsDao: db.userSettingsDao,
        markets: MarketRegistry(),
        clock: now,
        random: Random(1),
      );

      // Not a failure: the calendar runs on the shipped catalog, which is what
      // it did before this channel existed.
      expect((await offline.refreshOverrides(force: true)).isRight(), isTrue);
    });
  });
}
