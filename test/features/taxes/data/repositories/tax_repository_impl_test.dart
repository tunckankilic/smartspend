import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/market_registry.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/data/repositories/tax_repository_impl.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

import '../../../../helpers/test_database.dart';

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
}
