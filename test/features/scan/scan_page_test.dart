import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/presentation/bloc/scan_bloc.dart';
import 'package:smartspend/features/scan/presentation/pages/scan_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockScanBloc extends MockBloc<ScanEvent, ScanState>
    implements ScanBloc {}

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

  setUpAll(() {
    registerFallbackValue(const ScanReset());
  });

  setUp(() {
    bloc = _MockScanBloc();
    sl.registerFactory<ScanBloc>(() => bloc);
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
