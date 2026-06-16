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
  });
}
