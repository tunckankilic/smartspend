import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/market_registry.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/data/repositories/tax_repository_impl.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';
import 'package:smartspend/features/taxes/domain/usecases/annotate_tax_obligation.dart';
import 'package:smartspend/features/taxes/domain/usecases/mark_tax_obligation.dart';
import 'package:smartspend/features/taxes/domain/usecases/save_tax_profile.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_calendar_cubit.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_obligation_detail_cubit.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_profile_wizard_cubit.dart';

import '../../../../helpers/recording_telemetry_service.dart';
import '../../../../helpers/test_database.dart';


/// Counts the override pull and delegates everything else to the real thing.
///
/// The launch-time pull is the only thing that makes the override channel run
/// at all; a repository that supports it and a cubit that never calls it is a
/// channel that exists only in tests.
class _CountingRepository implements TaxRepository {
  _CountingRepository(this._inner);

  final TaxRepository _inner;
  int refreshCalls = 0;
  bool? lastForce;
  Exception? refreshThrows;

  @override
  Future<Either<Failure, void>> refreshOverrides({bool force = false}) async {
    refreshCalls++;
    lastForce = force;
    final Exception? boom = refreshThrows;
    if (boom != null) {
      throw boom;
    }
    return _inner.refreshOverrides(force: force);
  }

  @override
  Future<Either<Failure, TaxpayerProfile>> getProfile() => _inner.getProfile();

  @override
  Future<Either<Failure, void>> saveProfile(TaxpayerProfile profile) =>
      _inner.saveProfile(profile);

  @override
  Stream<TaxCalendarSnapshot> watchCalendar() => _inner.watchCalendar();

  @override
  Future<Either<Failure, void>> regenerate() => _inner.regenerate();

  @override
  Future<Either<Failure, TaxCalendarItem?>> getItem(int id) =>
      _inner.getItem(id);

  @override
  Future<Either<Failure, void>> setDeclared(int id, DateTime? at) =>
      _inner.setDeclared(id, at);

  @override
  Future<Either<Failure, void>> setPaid(int id, DateTime? at) =>
      _inner.setPaid(id, at);

  @override
  Future<Either<Failure, void>> setDismissed(int id, DateTime? at) =>
      _inner.setDismissed(id, at);

  @override
  Future<Either<Failure, void>> setAmount(
    int id, {
    required int? amountMinor,
    required TaxAmountSource source,
  }) =>
      _inner.setAmount(id, amountMinor: amountMinor, source: source);

  @override
  Future<Either<Failure, void>> setNote(int id, String? note) =>
      _inner.setNote(id, note);

  @override
  Future<Either<Failure, void>> setUserDueDates(
    int id, {
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
  }) =>
      _inner.setUserDueDates(
        id,
        declarationDueDate: declarationDueDate,
        paymentDueDate: paymentDueDate,
      );

  @override
  Future<Either<Failure, int>> addCustomItem({
    required String title,
    required DateTime dueDate,
    bool isPayment = true,
    String? note,
  }) =>
      _inner.addCustomItem(
        title: title,
        dueDate: dueDate,
        isPayment: isPayment,
        note: note,
      );
}

void main() {
  late AppDatabase db;
  late TaxRepository repository;
  late RecordingTelemetryService telemetry;

  // Mid-September, fixed. Every derived state on these screens is a function
  // of "today", so a wall-clock test would drift into different answers.
  DateTime now() => DateTime.utc(2026, 9, 15, 10);

  setUp(() {
    db = createTestDatabase();
    telemetry = RecordingTelemetryService();
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

  const TaxpayerProfile answered = TaxpayerProfile(
    legalForm: TaxpayerLegalForm.sahisSirketi,
    vatLiability: VatLiability.monthly,
    withholdingLiability: WithholdingLiability.none,
    employsStaff: TaxpayerAnswer.no,
    bagkurInsured: TaxpayerAnswer.yes,
    usesELedger: TaxpayerAnswer.no,
    ownsVehicle: TaxpayerAnswer.no,
    ownsRealEstate: TaxpayerAnswer.no,
  );

  group('TaxProfileWizardCubit', () {
    TaxProfileWizardCubit build() => TaxProfileWizardCubit(
          repository: repository,
          saveProfile: SaveTaxProfileUseCase(
            repository: repository,
            telemetry: telemetry,
          ),
        );

    test('should start on the first of eight questions', () {
      final TaxProfileWizardCubit cubit = build();
      addTearDown(cubit.close);

      expect(cubit.state.stepIndex, 0);
      expect(cubit.state.stepCount, 8);
      expect(cubit.state.step, TaxWizardStep.legalForm);
      expect(cubit.state.isLastStep, isFalse);
    });

    test('should walk forwards and backwards without falling off', () {
      final TaxProfileWizardCubit cubit = build();
      addTearDown(cubit.close);

      cubit.back();
      expect(cubit.state.stepIndex, 0, reason: 'no step before the first');

      for (int i = 0; i < 20; i++) {
        cubit.next();
      }
      expect(cubit.state.stepIndex, 7);
      expect(cubit.state.isLastStep, isTrue);
    });

    test('should keep an unanswered question unanswered', () async {
      // Skipping is a first-class outcome. The generator turns `unknown` into
      // a visible gap; a wizard that filled something in would produce a
      // fuller-looking calendar built on answers nobody gave.
      final TaxProfileWizardCubit cubit = build();
      addTearDown(cubit.close);

      cubit
        ..answer(
          cubit.state.profile.copyWith(
            legalForm: TaxpayerLegalForm.limited,
          ),
        )
        ..next();
      await cubit.submit();

      final TaxpayerProfile stored = await db.taxProfileDao.getProfile();
      expect(stored.legalForm, TaxpayerLegalForm.limited);
      expect(stored.vatLiability, VatLiability.unknown);
      expect(stored.isComplete, isFalse);
    });

    test('should save a partial profile rather than refuse it', () async {
      final TaxProfileWizardCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.submit();

      expect(cubit.state.status, TaxProfileWizardStatus.saved);
      expect(telemetry.keys, <String>['tax_profile_completed']);
    });

    test('should reopen on the answers already stored', () async {
      await repository.saveProfile(answered);

      final TaxProfileWizardCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load();

      expect(cubit.state.profile.legalForm, TaxpayerLegalForm.sahisSirketi);
      expect(cubit.state.profile.bagkurInsured, TaxpayerAnswer.yes);
    });
  });

  group('TaxCalendarCubit', () {
    TaxCalendarCubit build() =>
        TaxCalendarCubit(repository: repository, clock: now);

    test('should generate on subscribe, not only on a profile change',
        () async {
      // A month boundary brings new periods into range; a user opening the
      // app in November must not have to re-answer the wizard to see
      // December.
      await repository.saveProfile(answered);
      final TaxCalendarCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, isA<TaxCalendarLoaded>());
      expect((cubit.state as TaxCalendarLoaded).snapshot.items, isNotEmpty);
    });


    test('should pull published corrections on subscribe', () async {
      // Without this the override channel never runs on a real device: nothing
      // else calls it, and every deadline stays at whatever the binary shipped.
      final _CountingRepository counting = _CountingRepository(repository);
      final TaxCalendarCubit cubit =
          TaxCalendarCubit(repository: counting, clock: now);
      addTearDown(cubit.close);

      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      expect(counting.refreshCalls, 1);
      expect(counting.lastForce, isFalse);
    });

    test('should show the calendar even when the pull blows up', () async {
      // The pull is fire-and-forget on purpose. Offline is the normal state,
      // and a screen that fails because the network did would be a worse bug
      // than a date six hours stale.
      final _CountingRepository counting = _CountingRepository(repository)
        ..refreshThrows = Exception('offline');
      await repository.saveProfile(answered);
      final TaxCalendarCubit cubit =
          TaxCalendarCubit(repository: counting, clock: now);
      addTearDown(cubit.close);

      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, isA<TaxCalendarLoaded>());
    });

    test('should report that no profile has been given yet', () async {
      final TaxCalendarCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as TaxCalendarLoaded).hasProfile, isFalse);
    });

    test('should keep the selected slice through a reload', () async {
      await repository.saveProfile(answered);
      final TaxCalendarCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      cubit.showRange(TaxCalendarRange.past);
      await repository.regenerate();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.range, TaxCalendarRange.past);
    });

    test('should show a dateless item in the current month', () async {
      // Today's normal case: every catalog rule is unverified, so nothing has
      // a deadline. Those items must land somewhere the user can find them
      // rather than falling out of every slice.
      await repository.saveProfile(answered);
      final TaxCalendarCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      final TaxCalendarLoaded state = cubit.state as TaxCalendarLoaded;
      expect(state.visible, isNotEmpty);
      expect(
        state.visible.every((TaxCalendarItem i) => !i.hasAnyDate),
        isTrue,
      );
    });

    test('should drop a dismissed item from the list but keep the row',
        () async {
      await repository.saveProfile(answered);
      final TaxCalendarCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);
      final TaxCalendarLoaded before = cubit.state as TaxCalendarLoaded;
      final int dismissedId = before.visible.first.id;

      await repository.setDismissed(dismissedId, DateTime.utc(2026, 9, 2));
      await Future<void>.delayed(Duration.zero);

      final TaxCalendarLoaded after = cubit.state as TaxCalendarLoaded;
      expect(
        after.visible.map((TaxCalendarItem i) => i.id),
        isNot(contains(dismissedId)),
      );
      // The row survives — it is the signal that the calendar is wrong for
      // this taxpayer, and deleting it would only have it regenerated.
      expect(
        after.snapshot.items.map((TaxCalendarItem i) => i.id),
        contains(dismissedId),
      );
    });

    test('should surface the gaps the generator reported', () async {
      await repository.saveProfile(
        const TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
      );
      final TaxCalendarCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as TaxCalendarLoaded).snapshot.gaps, isNotEmpty);
    });

    test('should sort a dated item ahead of a dateless one', () async {
      await repository.addCustomItem(
        title: 'Dated',
        dueDate: DateTime.utc(2026, 9, 20),
      );
      await repository.saveProfile(answered);
      final TaxCalendarCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.subscribe();
      await Future<void>.delayed(Duration.zero);

      final TaxCalendarLoaded state = cubit.state as TaxCalendarLoaded;
      expect(state.visible.first.title, 'Dated');
    });
  });

  group('TaxObligationDetailCubit', () {
    TaxObligationDetailCubit build() => TaxObligationDetailCubit(
          repository: repository,
          mark: MarkTaxObligationUseCase(
            repository: repository,
            telemetry: telemetry,
          ),
          annotate: AnnotateTaxObligationUseCase(
            repository: repository,
            telemetry: telemetry,
          ),
          clock: now,
        );

    Future<int> seedItem() async {
      await repository.addCustomItem(
        title: 'Kira stopajı',
        dueDate: DateTime.utc(2026, 9, 20),
      );
      return (await repository.watchCalendar().first).items.single.id;
    }

    test('should load the item and derive its state', () async {
      final int id = await seedItem();
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.load(id);

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.item!.title, 'Kira stopajı');
      expect(cubit.state.itemState, TaxObligationState.upcoming);
      expect(cubit.state.today, DateTime.utc(2026, 9, 15));
    });

    test('should complete once the only step that exists is marked', () async {
      // The custom item has a payment deadline and no filing step, so paying
      // it finishes it. Requiring both marks would leave it permanently open.
      final int id = await seedItem();
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load(id);

      await cubit.setPaid(paid: true);

      expect(cubit.state.itemState, TaxObligationState.completed);
    });

    test('should let a mark be taken back', () async {
      final int id = await seedItem();
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load(id);
      await cubit.setPaid(paid: true);

      await cubit.setPaid(paid: false);

      expect(cubit.state.item!.paidAt, isNull);
      expect(cubit.state.itemState, TaxObligationState.upcoming);
    });

    test('should record a dismissal and reflect it in the state', () async {
      final int id = await seedItem();
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load(id);

      await cubit.setDismissed(dismissed: true);

      expect(cubit.state.itemState, TaxObligationState.dismissed);
      expect(telemetry.keys, contains('tax_item_removed'));
    });

    test('should store an amount with the source that was chosen', () async {
      final int id = await seedItem();
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load(id);

      await cubit.setAmount(
        amountMinor: 125000,
        source: TaxAmountSource.accountant,
      );

      expect(cubit.state.item!.amountMinor, 125000);
      expect(cubit.state.item!.amountSource, TaxAmountSource.accountant);
    });

    test('should reset the source when the amount is cleared', () async {
      // A claim about who said a number, with no number attached, is noise.
      final int id = await seedItem();
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load(id);
      await cubit.setAmount(
        amountMinor: 125000,
        source: TaxAmountSource.accountant,
      );

      await cubit.setAmount(
        amountMinor: null,
        source: TaxAmountSource.accountant,
      );

      expect(cubit.state.item!.amountMinor, isNull);
      expect(cubit.state.item!.amountSource, TaxAmountSource.unknown);
    });

    test('should treat a blank note as clearing it', () async {
      final int id = await seedItem();
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);
      await cubit.load(id);
      await cubit.setNote('bir not');

      await cubit.setNote('   ');

      expect(cubit.state.item!.note, isNull);
    });

    test('should do nothing when no item is loaded', () async {
      final TaxObligationDetailCubit cubit = build();
      addTearDown(cubit.close);

      await cubit.setPaid(paid: true);
      await cubit.setNote('x');

      expect(cubit.state.item, isNull);
      expect(telemetry.keys, isEmpty);
    });
  });
}
