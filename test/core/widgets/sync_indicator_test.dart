import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/widgets/sync_indicator.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

import 'package:dartz/dartz.dart';

class _MockSyncService extends Mock implements SyncService {}

void main() {
  late _MockSyncService syncService;

  setUp(() {
    syncService = _MockSyncService();
    when(() => syncService.sync()).thenAnswer(
      (_) async => const Right<Failure, SyncReport>(SyncReport()),
    );
    if (sl.isRegistered<SyncService>()) {
      sl.unregister<SyncService>();
    }
    sl.registerSingleton<SyncService>(syncService);
  });

  tearDown(() {
    sl.unregister<SyncService>();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: AppBar(actions: <Widget>[child]),
      ),
    );
  }

  testWidgets('shows the offline icon when the engine is offline',
      (WidgetTester tester) async {
    when(() => syncService.watchStatus())
        .thenAnswer((_) => Stream<SyncPhase>.value(const SyncPhaseOffline()));

    await tester.pumpWidget(wrap(const SyncIndicator()));
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('shows the syncing icon while a run is in flight',
      (WidgetTester tester) async {
    when(() => syncService.watchStatus())
        .thenAnswer((_) => Stream<SyncPhase>.value(const SyncPhaseSyncing()));

    await tester.pumpWidget(wrap(const SyncIndicator()));
    await tester.pump();

    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('tapping the indicator triggers a manual sync',
      (WidgetTester tester) async {
    when(() => syncService.watchStatus()).thenAnswer(
      (_) => Stream<SyncPhase>.value(const SyncPhaseSynced()),
    );

    await tester.pumpWidget(wrap(const SyncIndicator()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.cloud_done_outlined));
    await tester.pump();

    verify(() => syncService.sync()).called(1);
  });
}
