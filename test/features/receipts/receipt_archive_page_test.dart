import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_archive_bloc.dart';
import 'package:smartspend/features/receipts/presentation/pages/receipt_archive_page.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockReceiptArchiveBloc
    extends MockBloc<ReceiptArchiveEvent, ReceiptArchiveState>
    implements ReceiptArchiveBloc {}

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

ReceiptArchiveEntry _entry({int id = 1}) {
  return ReceiptArchiveEntry(
    id: id,
    date: DateTime.utc(2026, 5, 20),
    totalMinor: 4250,
    currency: 'TRY',
    storeName: 'Migros',
  );
}

void main() {
  late _MockReceiptArchiveBloc bloc;
  late _MockSyncCubit syncCubit;

  setUpAll(() {
    registerFallbackValue(const ReceiptArchiveSubscribed());
  });

  setUp(() {
    bloc = _MockReceiptArchiveBloc();
    syncCubit = _MockSyncCubit();
    when(() => syncCubit.state).thenReturn(const SyncIdle());
    sl.registerFactory<ReceiptArchiveBloc>(() => bloc);
  });

  tearDown(() async {
    await sl.reset();
    await syncCubit.close();
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
      home: BlocProvider<SyncCubit>.value(
        value: syncCubit,
        child: const ReceiptArchivePage(),
      ),
    );
  }

  group('ReceiptArchivePage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(const ReceiptArchiveLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders a grid of cards once loaded', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        ReceiptArchiveLoaded(
          entries: <ReceiptArchiveEntry>[_entry()],
          filter: ReceiptArchiveFilter.empty,
          layout: ReceiptArchiveLayout.grid,
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('archive.grid')), findsOneWidget);
      expect(find.text('Migros'), findsOneWidget);
    });

    testWidgets('renders a list of cards when layout is list', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        ReceiptArchiveLoaded(
          entries: <ReceiptArchiveEntry>[_entry()],
          filter: ReceiptArchiveFilter.empty,
          layout: ReceiptArchiveLayout.list,
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('archive.list')), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('shows the empty state message when there are no entries', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ReceiptArchiveLoaded(
          entries: <ReceiptArchiveEntry>[],
          filter: ReceiptArchiveFilter.empty,
          layout: ReceiptArchiveLayout.grid,
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('archive.grid')), findsNothing);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('shows an error message on a hard failure', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const ReceiptArchiveError(failure: CacheFailure(message: 'broke')),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        ReceiptArchiveLoaded(
          entries: <ReceiptArchiveEntry>[_entry()],
          filter: ReceiptArchiveFilter.empty,
          layout: ReceiptArchiveLayout.grid,
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
