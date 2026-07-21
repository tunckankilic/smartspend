import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failure_codes.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/presentation/bloc/ai_consent_cubit.dart';
import 'package:smartspend/features/scan/presentation/bloc/scan_bloc.dart';
import 'package:smartspend/features/scan/presentation/pages/scan_page.dart';
import 'package:smartspend/features/scan/presentation/widgets/scan_ai_consent_dialog.dart';
import 'package:smartspend/features/settings/domain/entities/ai_consent_status.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_ai_consent.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockScanBloc extends MockBloc<ScanEvent, ScanState>
    implements ScanBloc {}

class _MockGetPreferences extends Mock implements GetPreferencesUseCase {}

class _MockSetAiConsent extends Mock implements SetAiConsentUseCase {}

const ScannedReceipt _receipt = ScannedReceipt(
  imagePath: '/tmp/receipt.jpg',
  items: <ScannedItem>[],
  total: 1999,
  currency: 'TRY',
  rawText: 'raw',
  confidenceScore: 0.9,
  storeName: 'Migros',
);

void main() {
  late _MockScanBloc bloc;
  late _MockGetPreferences getPreferences;
  late _MockSetAiConsent setAiConsent;

  setUpAll(() {
    registerFallbackValue(const ScanReset());
    registerFallbackValue(const NoParams());
  });

  void mockAiConsent(AiConsentStatus status) {
    when(() => getPreferences(any())).thenAnswer(
      (_) async => Right<Failure, UserPreferences>(
        UserPreferences.defaults.copyWith(aiConsent: status),
      ),
    );
  }

  setUp(() {
    bloc = _MockScanBloc();
    getPreferences = _MockGetPreferences();
    setAiConsent = _MockSetAiConsent();
    mockAiConsent(AiConsentStatus.granted);
    when(
      () => setAiConsent(any()),
    ).thenAnswer((_) async => const Right<Failure, Unit>(unit));
    sl
      ..registerFactory<ScanBloc>(() => bloc)
      ..registerFactory<AiConsentCubit>(
        () => AiConsentCubit(
          getPreferences: getPreferences,
          setAiConsent: setAiConsent,
        ),
      );
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget wrap({
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      home: const ScanPage(),
    );
  }

  group('ScanPage', () {
    testWidgets('renders the intro panel with capture/gallery actions', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const ScanInitial());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byIcon(Icons.document_scanner_rounded), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
    });

    testWidgets('shows a spinner while processing', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const ScanProcessing());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the error panel with a retry action on failure', (
      WidgetTester tester,
    ) async {
      when(
        () => bloc.state,
      ).thenReturn(const ScanError(failure: PermissionFailure(message: 'x')));
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    testWidgets('shows the saved panel after a successful save', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const ScanSaved(receipt: _receipt));
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byIcon(Icons.savings_rounded), findsOneWidget);
    });

    testWidgets(
      'asks for AI consent on first capture and records the choice',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(const ScanInitial());
        mockAiConsent(AiConsentStatus.notAsked);
        await tester.pumpWidget(wrap());
        await tester.pump();

        await tester.tap(find.byIcon(Icons.photo_library_rounded));
        await tester.pumpAndSettle();

        // Consent dialog is up; the gallery event must wait for the answer.
        expect(find.byType(ScanAiConsentDialog), findsOneWidget);
        verifyNever(() => bloc.add(const GalleryOpened()));

        await tester.tap(find.text('Allow'));
        await tester.pumpAndSettle();

        expect(find.byType(ScanAiConsentDialog), findsNothing);
        verify(() => setAiConsent(true)).called(1);
        verify(() => bloc.add(const GalleryOpened())).called(1);
      },
    );

    testWidgets(
      'records a denial and still proceeds with on-device scanning',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(const ScanInitial());
        mockAiConsent(AiConsentStatus.notAsked);
        await tester.pumpWidget(wrap());
        await tester.pump();

        await tester.tap(find.byIcon(Icons.photo_library_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text("Don't Allow"));
        await tester.pumpAndSettle();

        verify(() => setAiConsent(false)).called(1);
        verify(() => bloc.add(const GalleryOpened())).called(1);
      },
    );

    testWidgets(
      'skips the consent dialog when the user already decided',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(const ScanInitial());
        mockAiConsent(AiConsentStatus.granted);
        await tester.pumpWidget(wrap());
        await tester.pump();

        await tester.tap(find.byIcon(Icons.photo_library_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(ScanAiConsentDialog), findsNothing);
        verify(() => bloc.add(const GalleryOpened())).called(1);
      },
    );

    testWidgets(
      'shows the AI status row on the intro panel and reflects consent',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(const ScanInitial());
        mockAiConsent(AiConsentStatus.granted);
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        expect(find.text('AI-enhanced scanning: On'), findsOneWidget);

        // Tear the tree down so a fresh page (and cubit) is created for
        // the denied variant — element reuse would keep the old cubit.
        await tester.pumpWidget(const SizedBox.shrink());
        mockAiConsent(AiConsentStatus.denied);
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        expect(find.text('AI-enhanced scanning: Off'), findsOneWidget);
      },
    );

    testWidgets(
      'lets the user change consent from the intro status row',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(const ScanInitial());
        mockAiConsent(AiConsentStatus.denied);
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        await tester.tap(find.text('AI-enhanced scanning: Off'));
        await tester.pumpAndSettle();

        expect(find.byType(ScanAiConsentDialog), findsOneWidget);
        await tester.tap(find.text('Allow'));
        await tester.pumpAndSettle();

        verify(() => setAiConsent(true)).called(1);
        expect(find.text('AI-enhanced scanning: On'), findsOneWidget);
      },
    );

    testWidgets(
      'offers a contextual AI re-ask when OCR failed without consent',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          ScanError(
            failure: const OCRFailure(
              message: 'no consent',
              code: kOcrNoAiConsentCode,
            ),
            image: File('/tmp/receipt.jpg'),
          ),
        );
        mockAiConsent(AiConsentStatus.denied);
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        expect(find.text('Try Again with AI'), findsOneWidget);

        await tester.tap(find.text('Try Again with AI'));
        await tester.pumpAndSettle();

        expect(find.byType(ScanAiConsentDialog), findsOneWidget);
        await tester.tap(find.text('Allow'));
        await tester.pumpAndSettle();

        verify(() => setAiConsent(true)).called(1);
        verify(() => bloc.add(const ScanRetried())).called(1);
      },
    );

    testWidgets(
      'keeps the error screen when the AI re-ask is declined again',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          ScanError(
            failure: const OCRFailure(
              message: 'no consent',
              code: kOcrNoAiConsentCode,
            ),
            image: File('/tmp/receipt.jpg'),
          ),
        );
        mockAiConsent(AiConsentStatus.denied);
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Try Again with AI'));
        await tester.pumpAndSettle();
        await tester.tap(find.text("Don't Allow"));
        await tester.pumpAndSettle();

        verify(() => setAiConsent(false)).called(1);
        verifyNever(() => bloc.add(const ScanRetried()));
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'shows only the plain retry on consent failure without an image',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          const ScanError(
            failure: OCRFailure(
              message: 'no consent',
              code: kOcrNoAiConsentCode,
            ),
          ),
        );
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        expect(find.text('Try Again with AI'), findsNothing);
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      },
    );

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const ScanSaved(receipt: _receipt));

      for (final Locale locale in const <Locale>[
        Locale('tr'),
        Locale('en'),
        Locale('de'),
      ]) {
        for (final ThemeMode mode in const <ThemeMode>[
          ThemeMode.light,
          ThemeMode.dark,
        ]) {
          await tester.pumpWidget(wrap(locale: locale, themeMode: mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
