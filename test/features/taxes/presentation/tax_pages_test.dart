import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/tax_calendar_generator.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/usecases/add_custom_tax_item.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_calendar_cubit.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_obligation_detail_cubit.dart';
import 'package:smartspend/features/taxes/presentation/cubit/tax_profile_wizard_cubit.dart';
import 'package:smartspend/features/taxes/presentation/pages/add_custom_tax_item_page.dart';
import 'package:smartspend/features/taxes/presentation/pages/tax_calendar_page.dart';
import 'package:smartspend/features/taxes/presentation/pages/tax_obligation_detail_page.dart';
import 'package:smartspend/features/taxes/presentation/pages/tax_profile_wizard_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

class _MockCalendarCubit extends MockCubit<TaxCalendarState>
    implements TaxCalendarCubit {}

class _MockWizardCubit extends MockCubit<TaxProfileWizardState>
    implements TaxProfileWizardCubit {}

class _MockDetailCubit extends MockCubit<TaxObligationDetailState>
    implements TaxObligationDetailCubit {}

class _MockAddCustomUseCase extends Mock implements AddCustomTaxItemUseCase {}

class _FakeAddCustomParams extends Fake implements AddCustomTaxItemParams {}

/// Pushes [child] from a real route, so a page that pops on success has
/// something to pop back to.
class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('host.open'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (BuildContext _) => child),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

TaxCalendarItem item({
  int id = 1,
  TaxObligationKind kind = TaxObligationKind.kdv1,
  DateTime? declarationDue,
  DateTime? paymentDue,
  bool hasDeclarationStep = true,
  bool hasPaymentStep = true,
  bool needsDateWarning = true,
  DateTime? declaredAt,
  DateTime? paidAt,
  DateTime? dismissedAt,
  int? amountMinor,
  TaxAmountSource amountSource = TaxAmountSource.unknown,
  String? note,
}) =>
    TaxCalendarItem(
      id: id,
      kind: kind,
      nameL10nKey: kind.l10nKey,
      periodKind: TaxPeriodKind.monthly,
      periodStart: DateTime.utc(2026, 8),
      periodEnd: DateTime.utc(2026, 8, 31),
      installmentIndex: 0,
      dueDateSource: TaxDueDateSource.catalog,
      amountSource: amountSource,
      hasDeclarationStep: hasDeclarationStep,
      hasPaymentStep: hasPaymentStep,
      isConditional: false,
      needsDateWarning: needsDateWarning,
      isUserDefined: false,
      declarationDueDate: declarationDue,
      paymentDueDate: paymentDue,
      declaredAt: declaredAt,
      paidAt: paidAt,
      dismissedAt: dismissedAt,
      amountMinor: amountMinor,
      note: note,
    );

void main() {
  late _MockSyncCubit syncCubit;
  late AppLocalizations l;

  final DateTime today = DateTime.utc(2026, 9, 15);

  const TaxpayerProfile answered = TaxpayerProfile(
    legalForm: TaxpayerLegalForm.sahisSirketi,
    vatLiability: VatLiability.monthly,
  );

  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('tr'));
    registerFallbackValue(_FakeAddCustomParams());
    registerFallbackValue(TaxCalendarRange.thisMonth);
    registerFallbackValue(TaxpayerProfile.empty);
    registerFallbackValue(TaxAmountSource.unknown);
  });

  setUp(() {
    syncCubit = _MockSyncCubit();
    when(() => syncCubit.state).thenReturn(const SyncIdle());
  });

  tearDown(() async {
    await sl.reset();
    await syncCubit.close();
  });

  Widget wrap(Widget child, {bool hosted = false}) => MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<SyncCubit>.value(
          value: syncCubit,
          child: hosted ? _Host(child: child) : child,
        ),
      );

  group('TaxCalendarPage', () {
    late _MockCalendarCubit cubit;

    setUp(() {
      cubit = _MockCalendarCubit();
      when(cubit.subscribe).thenAnswer((_) async {});
      when(() => cubit.showRange(any())).thenReturn(null);
      sl.registerFactory<TaxCalendarCubit>(() => cubit);
    });

    void withState(TaxCalendarState state) =>
        when(() => cubit.state).thenReturn(state);

    TaxCalendarLoaded loaded({
      List<TaxCalendarItem> items = const <TaxCalendarItem>[],
      List<TaxCalendarGap> gaps = const <TaxCalendarGap>[],
      TaxpayerProfile profile = answered,
      TaxCalendarRange range = TaxCalendarRange.thisMonth,
    }) =>
        TaxCalendarLoaded(
          snapshot: TaxCalendarSnapshot(
            items: items,
            gaps: gaps,
            profile: profile,
          ),
          visible: items,
          today: today,
          range: range,
        );

    testWidgets('shows a spinner before the first snapshot',
        (WidgetTester tester) async {
      withState(const TaxCalendarLoading());

      await tester.pumpWidget(wrap(const TaxCalendarPage()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('invites the user to fill the profile before anything else',
        (WidgetTester tester) async {
      withState(loaded(profile: TaxpayerProfile.empty));

      await tester.pumpWidget(wrap(const TaxCalendarPage()));
      await tester.pump();

      expect(find.byKey(const Key('tax.calendar.noProfile')), findsOneWidget);
      expect(find.text(l.taxCalendarNoProfileAction), findsOneWidget);
    });

    testWidgets('lists the items and hedges their dates',
        (WidgetTester tester) async {
      withState(
        loaded(
          items: <TaxCalendarItem>[
            item(declarationDue: DateTime.utc(2026, 9, 26)),
          ],
        ),
      );

      await tester.pumpWidget(wrap(const TaxCalendarPage()));
      await tester.pump();

      expect(find.text(l.taxObligationKdv1), findsOneWidget);
      expect(find.byKey(const Key('tax.card.dateWarning')), findsOneWidget);
      // The list is only true as of the day it was derived, and says so.
      expect(find.textContaining(l.taxCalendarAsOf('')), findsOneWidget);
      expect(find.byKey(const Key('tax.calendar.range')), findsOneWidget);
    });

    testWidgets('says when a slice is empty', (WidgetTester tester) async {
      withState(loaded());

      await tester.pumpWidget(wrap(const TaxCalendarPage()));
      await tester.pump();

      expect(find.byKey(const Key('tax.calendar.empty')), findsOneWidget);
    });

    testWidgets('shows what could not be generated',
        (WidgetTester tester) async {
      withState(
        loaded(
          items: <TaxCalendarItem>[item()],
          gaps: const <TaxCalendarGap>[
            TaxCalendarGap(
              kind: TaxObligationKind.mphb,
              reason: TaxCalendarGapReason.recurrenceUnknown,
            ),
          ],
        ),
      );

      await tester.pumpWidget(wrap(const TaxCalendarPage()));
      await tester.pump();

      expect(find.byKey(const Key('tax.calendar.gaps')), findsOneWidget);
      expect(find.text(l.taxObligationMphb), findsOneWidget);
    });

    testWidgets('asks the cubit to switch slices',
        (WidgetTester tester) async {
      withState(loaded(items: <TaxCalendarItem>[item()]));

      await tester.pumpWidget(wrap(const TaxCalendarPage()));
      await tester.pump();
      await tester.tap(find.text(l.taxCalendarRangePast));
      await tester.pump();

      verify(() => cubit.showRange(TaxCalendarRange.past)).called(1);
    });

    testWidgets('surfaces a stream failure', (WidgetTester tester) async {
      withState(
        const TaxCalendarError(failure: CacheFailure(message: 'broken')),
      );

      await tester.pumpWidget(wrap(const TaxCalendarPage()));
      await tester.pump();

      expect(find.textContaining('broken'), findsOneWidget);
    });
  });

  group('TaxProfileWizardPage', () {
    late _MockWizardCubit cubit;

    setUp(() {
      cubit = _MockWizardCubit();
      when(cubit.load).thenAnswer((_) async {});
      when(cubit.next).thenReturn(null);
      when(cubit.back).thenReturn(null);
      when(() => cubit.answer(any())).thenReturn(null);
      when(cubit.submit).thenAnswer((_) async {});
      sl.registerFactory<TaxProfileWizardCubit>(() => cubit);
    });

    void withState(TaxProfileWizardState state) =>
        when(() => cubit.state).thenReturn(state);

    testWidgets('asks the first question with skip in reach',
        (WidgetTester tester) async {
      // Skipping must be as easy as answering: the honest answer to "do you
      // keep books as e-Defter" is often "no idea", and a user who guesses to
      // get past the screen poisons their own calendar.
      withState(const TaxProfileWizardState());

      await tester.pumpWidget(wrap(const TaxProfileWizardPage()));
      await tester.pump();

      expect(find.text(l.taxWizardQuestionLegalForm), findsOneWidget);
      expect(find.text(l.taxWizardIntro), findsOneWidget);
      expect(find.byKey(const Key('tax.wizard.skip')), findsOneWidget);
      expect(find.byKey(const Key('tax.wizard.back')), findsNothing);
      expect(find.text(l.taxWizardStep(1, 8)), findsOneWidget);
    });

    testWidgets('offers "I\'d rather not say" as a real option',
        (WidgetTester tester) async {
      // The legal form is the D-2 bucket. Declining is an answer, not an
      // escape hatch you reach by force-quitting.
      withState(const TaxProfileWizardState());

      await tester.pumpWidget(wrap(const TaxProfileWizardPage()));
      await tester.pump();

      expect(find.text(l.taxLegalFormUnspecified), findsOneWidget);
    });

    testWidgets('records the option that was tapped',
        (WidgetTester tester) async {
      withState(const TaxProfileWizardState());

      await tester.pumpWidget(wrap(const TaxProfileWizardPage()));
      await tester.pump();
      await tester.tap(find.text(l.taxLegalFormLimited));
      await tester.pump();

      final TaxpayerProfile captured =
          verify(() => cubit.answer(captureAny())).captured.single
              as TaxpayerProfile;
      expect(captured.legalForm, TaxpayerLegalForm.limited);
    });

    testWidgets('advances on next and on skip alike',
        (WidgetTester tester) async {
      withState(const TaxProfileWizardState(stepIndex: 3));

      await tester.pumpWidget(wrap(const TaxProfileWizardPage()));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tax.wizard.next')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tax.wizard.skip')));
      await tester.pump();

      verify(cubit.next).called(2);
    });

    testWidgets('submits on the last step whichever button is used',
        (WidgetTester tester) async {
      withState(const TaxProfileWizardState(stepIndex: 7));

      await tester.pumpWidget(wrap(const TaxProfileWizardPage()));
      await tester.pump();

      expect(find.text(l.taxWizardFinish), findsOneWidget);
      await tester.tap(find.byKey(const Key('tax.wizard.skip')));
      await tester.pump();

      verify(cubit.submit).called(1);
    });

    testWidgets('shows the yes/no/unknown options on a yes-no question',
        (WidgetTester tester) async {
      withState(const TaxProfileWizardState(stepIndex: 3));

      await tester.pumpWidget(wrap(const TaxProfileWizardPage()));
      await tester.pump();

      expect(find.text(l.taxWizardQuestionEmploysStaff), findsOneWidget);
      expect(find.text(l.taxAnswerYes), findsOneWidget);
      expect(find.text(l.taxAnswerNo), findsOneWidget);
      expect(find.text(l.taxAnswerUnknown), findsOneWidget);
    });

    testWidgets('reports a failed save instead of pretending it worked',
        (WidgetTester tester) async {
      whenListen(
        cubit,
        Stream<TaxProfileWizardState>.fromIterable(
          <TaxProfileWizardState>[
            const TaxProfileWizardState(
              status: TaxProfileWizardStatus.failure,
              failure: CacheFailure(message: 'disk'),
            ),
          ],
        ),
        initialState: const TaxProfileWizardState(),
      );

      await tester.pumpWidget(wrap(const TaxProfileWizardPage()));
      await tester.pump();
      await tester.pump();

      expect(find.text(l.taxWizardSaveFailed), findsOneWidget);
    });
  });

  group('TaxObligationDetailPage', () {
    late _MockDetailCubit cubit;

    setUp(() {
      cubit = _MockDetailCubit();
      when(() => cubit.load(any())).thenAnswer((_) async {});
      when(() => cubit.setPaid(paid: any(named: 'paid')))
          .thenAnswer((_) async {});
      when(() => cubit.setDeclared(declared: any(named: 'declared')))
          .thenAnswer((_) async {});
      when(() => cubit.setDismissed(dismissed: any(named: 'dismissed')))
          .thenAnswer((_) async {});
      when(() => cubit.setNote(any())).thenAnswer((_) async {});
      when(
        () => cubit.setAmount(
          amountMinor: any(named: 'amountMinor'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async {});
      sl.registerFactory<TaxObligationDetailCubit>(() => cubit);
    });

    /// The detail page is a long ListView and the amount, note and dismiss
    /// controls sit below a phone-sized fold, where a lazy list never builds
    /// them. A tall surface builds the whole page instead of every test
    /// having to scroll first.
    Future<void> pumpDetail(WidgetTester tester, {int id = 1}) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(TaxObligationDetailPage(itemId: id)));
      await tester.pump();
    }

    void withItem(TaxCalendarItem? value, {bool loading = false}) =>
        when(() => cubit.state).thenReturn(
          TaxObligationDetailState(
            item: value,
            today: today,
            isLoading: loading,
          ),
        );

    testWidgets('shows two switches for two separate acts',
        (WidgetTester tester) async {
      withItem(
        item(
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
        ),
      );

      await pumpDetail(tester);

      expect(find.byKey(const Key('tax.detail.declared')), findsOneWidget);
      expect(find.byKey(const Key('tax.detail.paid')), findsOneWidget);
    });

    testWidgets('states that a step does not exist rather than hiding it',
        (WidgetTester tester) async {
      withItem(
        item(
          kind: TaxObligationKind.bagkur,
          hasDeclarationStep: false,
          paymentDue: DateTime.utc(2026, 9, 28),
        ),
      );

      await pumpDetail(tester);

      expect(find.byKey(const Key('tax.detail.declared')), findsNothing);
      expect(find.text(l.taxItemNoDeclaration), findsOneWidget);
    });

    testWidgets('marking paid does not touch the filing mark',
        (WidgetTester tester) async {
      withItem(
        item(
          declarationDue: DateTime.utc(2026, 9, 26),
          paymentDue: DateTime.utc(2026, 9, 28),
        ),
      );

      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('tax.detail.paid')));
      await tester.pump();

      verify(() => cubit.setPaid(paid: true)).called(1);
      verifyNever(() => cubit.setDeclared(declared: any(named: 'declared')));
    });

    testWidgets('says the app does not calculate the amount',
        (WidgetTester tester) async {
      withItem(item(paymentDue: DateTime.utc(2026, 9, 28)));

      await pumpDetail(tester);

      expect(
        find.byKey(const Key('tax.detail.amountDisclaimer')),
        findsOneWidget,
      );
      // Only the two human sources are offered — the enum has no third value.
      expect(find.text(l.taxDetailAmountSourceAccountant), findsOneWidget);
      expect(find.text(l.taxDetailAmountSourceUser), findsOneWidget);
    });

    testWidgets('reads a comma decimal as kuruş', (WidgetTester tester) async {
      // A Turkish keyboard produces a comma. Failing to parse would silently
      // drop the accountant's figure.
      withItem(item(paymentDue: DateTime.utc(2026, 9, 28)));

      await pumpDetail(tester);
      await tester.enterText(
        find.byKey(const Key('tax.detail.amountField')),
        '1250,50',
      );
      await tester.tap(find.byKey(const Key('tax.detail.saveAmount')));
      await tester.pump();

      verify(
        () => cubit.setAmount(
          amountMinor: 125050,
          source: TaxAmountSource.accountant,
        ),
      ).called(1);
    });

    testWidgets('clears the amount when the field is emptied',
        (WidgetTester tester) async {
      withItem(
        item(
          paymentDue: DateTime.utc(2026, 9, 28),
          amountMinor: 125000,
          amountSource: TaxAmountSource.accountant,
        ),
      );

      await pumpDetail(tester);
      await tester.enterText(
        find.byKey(const Key('tax.detail.amountField')),
        '',
      );
      await tester.tap(find.byKey(const Key('tax.detail.saveAmount')));
      await tester.pump();

      verify(
        () => cubit.setAmount(
          amountMinor: null,
          source: TaxAmountSource.accountant,
        ),
      ).called(1);
    });

    testWidgets('saves the note the user typed', (WidgetTester tester) async {
      withItem(item(paymentDue: DateTime.utc(2026, 9, 28)));

      await pumpDetail(tester);
      await tester.enterText(
        find.byKey(const Key('tax.detail.noteField')),
        'muhasebeci onayladı',
      );
      await tester.tap(find.byKey(const Key('tax.detail.saveNote')));
      await tester.pump();

      verify(() => cubit.setNote('muhasebeci onayladı')).called(1);
    });

    testWidgets('offers to undo a dismissal rather than hiding the item',
        (WidgetTester tester) async {
      withItem(
        item(
          paymentDue: DateTime.utc(2026, 9, 28),
          dismissedAt: DateTime.utc(2026, 9, 2),
        ),
      );

      await pumpDetail(tester);

      expect(find.text(l.taxDetailUndismiss), findsOneWidget);
      await tester.tap(find.byKey(const Key('tax.detail.dismiss')));
      await tester.pump();
      verify(() => cubit.setDismissed(dismissed: false)).called(1);
    });

    testWidgets('says so when the item is gone', (WidgetTester tester) async {
      withItem(null);

      await pumpDetail(tester, id: 999);

      expect(find.text(l.taxDetailNotFound), findsOneWidget);
    });

    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      withItem(null, loading: true);

      await pumpDetail(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('AddCustomTaxItemPage', () {
    late _MockAddCustomUseCase useCase;

    setUp(() {
      useCase = _MockAddCustomUseCase();
      sl.registerFactory<AddCustomTaxItemUseCase>(() => useCase);
    });

    testWidgets('refuses a nameless item before it reaches the use case',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const AddCustomTaxItemPage()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('tax.custom.save')));
      await tester.pump();

      expect(find.text(l.taxCustomNameRequired), findsOneWidget);
      verifyNever(() => useCase(any()));
    });

    testWidgets("saves the user's own deadline as a payment by default",
        (WidgetTester tester) async {
      when(() => useCase(any()))
          .thenAnswer((_) async => const Right<Failure, int>(7));

      await tester.pumpWidget(
        wrap(const AddCustomTaxItemPage(), hosted: true),
      );
      await tester.tap(find.byKey(const Key('host.open')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('tax.custom.title')),
        'Kira stopajı',
      );
      await tester.tap(find.byKey(const Key('tax.custom.save')));
      await tester.pumpAndSettle();

      final AddCustomTaxItemParams params =
          verify(() => useCase(captureAny())).captured.single
              as AddCustomTaxItemParams;
      expect(params.title, 'Kira stopajı');
      expect(params.isPayment, isTrue);
      expect(params.dueDate.isUtc, isTrue);
    });

    testWidgets('can record a filing deadline instead',
        (WidgetTester tester) async {
      when(() => useCase(any()))
          .thenAnswer((_) async => const Right<Failure, int>(7));

      await tester.pumpWidget(
        wrap(const AddCustomTaxItemPage(), hosted: true),
      );
      await tester.tap(find.byKey(const Key('host.open')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('tax.custom.title')),
        'Ek beyan',
      );
      await tester.tap(find.text(l.taxCustomKindDeclaration));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tax.custom.save')));
      await tester.pumpAndSettle();

      final AddCustomTaxItemParams params =
          verify(() => useCase(captureAny())).captured.single
              as AddCustomTaxItemParams;
      expect(params.isPayment, isFalse);
    });

    testWidgets('reports a failed save', (WidgetTester tester) async {
      when(() => useCase(any())).thenAnswer(
        (_) async => const Left<Failure, int>(CacheFailure(message: 'disk')),
      );

      await tester.pumpWidget(wrap(const AddCustomTaxItemPage()));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('tax.custom.title')),
        'Kira',
      );
      await tester.tap(find.byKey(const Key('tax.custom.save')));
      await tester.pump();

      expect(find.text(l.taxDetailSaveFailed), findsOneWidget);
    });
  });
}
