import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/widgets/sync_indicator.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

void main() {
  late _MockSyncCubit cubit;

  setUp(() {
    cubit = _MockSyncCubit();
    when(() => cubit.syncNow()).thenAnswer((_) async {});
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider<SyncCubit>.value(
        value: cubit,
        child: Scaffold(appBar: AppBar(actions: <Widget>[child])),
      ),
    );
  }

  testWidgets('shows the offline icon when the engine is offline',
      (WidgetTester tester) async {
    when(() => cubit.state).thenReturn(const SyncOffline());

    await tester.pumpWidget(wrap(const SyncIndicator()));
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('shows the syncing icon while a run is in flight',
      (WidgetTester tester) async {
    when(() => cubit.state).thenReturn(const SyncInProgress());

    await tester.pumpWidget(wrap(const SyncIndicator()));
    await tester.pump();

    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('tapping the indicator triggers a manual sync',
      (WidgetTester tester) async {
    when(() => cubit.state).thenReturn(const SyncSynced());

    await tester.pumpWidget(wrap(const SyncIndicator()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.cloud_done_outlined));
    await tester.pump();

    verify(() => cubit.syncNow()).called(1);
  });
}
