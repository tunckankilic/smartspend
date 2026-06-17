import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/presentation/bloc/receipt_edit_bloc.dart';
import 'package:smartspend/features/scan/presentation/pages/scan_result_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockReceiptEditBloc
    extends MockBloc<ReceiptEditEvent, ReceiptEditState>
    implements ReceiptEditBloc {}

const Category _groceries = Category(
  id: 1,
  name: 'Groceries',
  icon: 'shopping_cart',
  color: 0xFF4CAF50,
  isCustom: false,
);

const ScannedItem _item = ScannedItem(
  name: 'Süt',
  quantity: 2,
  unitPrice: 500,
  totalPrice: 1000,
  categoryId: 1,
);

const ScannedReceipt _receipt = ScannedReceipt(
  imagePath: '',
  items: <ScannedItem>[_item],
  total: 1000,
  currency: 'TRY',
  rawText: 'raw',
  confidenceScore: 0.9,
  storeName: 'Migros',
);

/// A receipt where OCR total (5000) differs from the item sum (1000)
/// by more than 50 minor units — triggers the mismatch warning row.
const ScannedReceipt _mismatchReceipt = ScannedReceipt(
  imagePath: '',
  items: <ScannedItem>[_item],
  total: 5000,
  currency: 'TRY',
  rawText: 'raw',
  confidenceScore: 0.9,
  storeName: 'Migros',
);

void main() {
  late _MockReceiptEditBloc bloc;

  setUpAll(() {
    registerFallbackValue(const ReceiptEditStarted(receipt: _receipt));
  });

  setUp(() {
    bloc = _MockReceiptEditBloc();
    sl.registerFactory<ReceiptEditBloc>(() => bloc);
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
      home: const ScanResultPage(receipt: _receipt),
    );
  }

  group('ScanResultPage', () {
    testWidgets('shows a spinner while categories are loading', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(const ReceiptEditInitial());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the edit form fields and the item card once ready', (
      WidgetTester tester,
    ) async {
      // Tall surface so the whole DraggableScrollableSheet form — including
      // the bottom action buttons — mounts without needing a manual scroll.
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      when(() => bloc.state).thenReturn(
        const ReceiptEditReady(
          receipt: _receipt,
          categories: <Category>[_groceries],
          defaultCategoryId: 1,
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsWidgets);
      expect(find.byType(TextField), findsWidgets);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('renders no body widgets on a recoverable failure state', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ReceiptEditFailure(failure: ServerFailure(message: 'x')),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ReceiptEditReady(
          receipt: _receipt,
          categories: <Category>[_groceries],
          defaultCategoryId: 1,
          validationErrors: <ReceiptEditValidationError>{
            ReceiptEditValidationError.emptyItems,
            ReceiptEditValidationError.futureDate,
          },
        ),
      );

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

    // -------------------------------------------------------------------------
    // New coverage: saving overlay, mismatch row, validation banner, listener
    // -------------------------------------------------------------------------

    testWidgets(
      'should show the saving overlay while persistence is in flight',
      (WidgetTester tester) async {
        when(() => bloc.state).thenReturn(
          const ReceiptEditSaving(receipt: _receipt),
        );
        await tester.pumpWidget(wrap());
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);
      },
    );

    testWidgets(
      'should show a mismatch warning when OCR total differs from item sum',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(
          const ReceiptEditReady(
            receipt: _mismatchReceipt,
            categories: <Category>[_groceries],
            defaultCategoryId: 1,
          ),
        );
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'should show an error icon for every entry in the validation banner',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(
          const ReceiptEditReady(
            receipt: _receipt,
            categories: <Category>[_groceries],
            defaultCategoryId: 1,
            validationErrors: <ReceiptEditValidationError>{
              ReceiptEditValidationError.emptyItems,
              ReceiptEditValidationError.nonPositiveTotal,
              ReceiptEditValidationError.futureDate,
              ReceiptEditValidationError.missingDefaultCategory,
            },
          ),
        );
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.error_outline_rounded), findsNWidgets(4));
      },
    );

    testWidgets(
      'should show a snackbar on save failure via the BlocConsumer listener',
      (WidgetTester tester) async {
        final StreamController<ReceiptEditState> ctrl =
            StreamController<ReceiptEditState>();
        whenListen(
          bloc,
          ctrl.stream,
          initialState: const ReceiptEditInitial(),
        );
        addTearDown(ctrl.close);

        await tester.pumpWidget(wrap());
        await tester.pump();

        ctrl.add(
          const ReceiptEditFailure(
            failure: ServerFailure(message: 'db error'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'should dispatch ReceiptItemAdded when the add-item button is tapped',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(
          const ReceiptEditReady(
            receipt: _receipt,
            categories: <Category>[_groceries],
            defaultCategoryId: 1,
          ),
        );
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();

        verify(
          () => bloc.add(const ReceiptItemAdded()),
        ).called(1);
      },
    );

    testWidgets(
      'should show save and retake buttons in the ready state',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(
          const ReceiptEditReady(
            receipt: _receipt,
            categories: <Category>[_groceries],
            defaultCategoryId: 1,
          ),
        );
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'should dispatch ReceiptEditSubmitted when save button is tapped',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => bloc.state).thenReturn(
          const ReceiptEditReady(
            receipt: _receipt,
            categories: <Category>[_groceries],
            defaultCategoryId: 1,
          ),
        );
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.check_rounded));
        await tester.pump();

        verify(
          () => bloc.add(const ReceiptEditSubmitted()),
        ).called(1);
      },
    );

    testWidgets(
      'should show the receipt-long placeholder when imagePath is empty',
      (WidgetTester tester) async {
        // _ImageHero is rendered in ReceiptEditSaving (behind the overlay).
        when(() => bloc.state).thenReturn(
          const ReceiptEditSaving(receipt: _receipt),
        );
        await tester.pumpWidget(wrap());
        await tester.pump();

        expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
      },
    );
  });
}
