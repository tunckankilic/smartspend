import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_detail.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_detail_bloc.dart';
import 'package:smartspend/features/receipts/presentation/pages/receipt_detail_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockReceiptDetailBloc
    extends MockBloc<ReceiptDetailEvent, ReceiptDetailState>
    implements ReceiptDetailBloc {}

const ReceiptDetailItem _item = ReceiptDetailItem(
  id: 1,
  name: 'Milk',
  quantity: 2,
  unitPriceMinor: 500,
  totalPriceMinor: 1000,
);

final ReceiptDetail _detail = ReceiptDetail(
  id: 1,
  date: DateTime.utc(2026, 5, 20),
  totalMinor: 1000,
  currency: 'TRY',
  items: const <ReceiptDetailItem>[_item],
  storeName: 'Migros',
);

void main() {
  late _MockReceiptDetailBloc bloc;

  setUpAll(() {
    registerFallbackValue(const ReceiptDetailLoaded(receiptId: 1));
  });

  setUp(() {
    bloc = _MockReceiptDetailBloc();
    sl.registerFactory<ReceiptDetailBloc>(() => bloc);
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
      home: const ReceiptDetailPage(receiptId: 1),
    );
  }

  group('ReceiptDetailPage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(const ReceiptDetailLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the store, total and items once ready', (
      WidgetTester tester,
    ) async {
      // Tall surface so the items list mounts without needing a scroll.
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      when(
        () => bloc.state,
      ).thenReturn(ReceiptDetailReady(detail: _detail));
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Migros'), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(find.byKey(const Key('warranty.add')), findsOneWidget);
    });

    testWidgets('renders the warranty end date when one is set', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        ReceiptDetailReady(
          detail: ReceiptDetail(
            id: _detail.id,
            date: _detail.date,
            totalMinor: _detail.totalMinor,
            currency: _detail.currency,
            items: _detail.items,
            storeName: _detail.storeName,
            warrantyEndDate: DateTime.utc(2027, 1, 1),
          ),
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('warranty.change')), findsOneWidget);
      expect(find.byKey(const Key('warranty.clear')), findsOneWidget);
    });

    testWidgets('shows the missing-receipt message on a hard failure', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ReceiptDetailError(failure: CacheFailure(message: 'broke')),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(
        () => bloc.state,
      ).thenReturn(ReceiptDetailReady(detail: _detail));

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
