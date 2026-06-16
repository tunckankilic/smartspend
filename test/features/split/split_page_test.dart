import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/split/domain/entities/participant.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/presentation/bloc/split_bloc.dart';
import 'package:smartspend/features/split/presentation/pages/split_page.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockSplitBloc extends MockBloc<SplitEvent, SplitState>
    implements SplitBloc {}

const SplitItem _item = SplitItem(
  id: 1,
  name: 'Milk',
  totalPriceMinor: 500,
);

final SplitSession _session = SplitSession(
  receiptId: 42,
  storeName: 'Market',
  receiptDate: DateTime.utc(2026, 6, 1),
  currency: 'TRY',
  totalMinor: 500,
  items: const <SplitItem>[_item],
  participants: const <Participant>[
    Participant(id: 'p1', name: 'Alice'),
    Participant(id: 'p2', name: 'Bob'),
  ],
  assignments: const <int, List<String>>{},
  splitType: SplitType.equal,
);

void main() {
  late _MockSplitBloc bloc;

  setUpAll(() {
    registerFallbackValue(const SplitStarted(receiptId: 1));
  });

  setUp(() {
    bloc = _MockSplitBloc();
    sl.registerFactory<SplitBloc>(() => bloc);
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
      home: const SplitPage(receiptId: 42),
    );
  }

  group('SplitPage', () {
    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      when(() => bloc.state).thenReturn(const SplitLoading());
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows an error message on failure', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const SplitError(failure: CacheFailure(message: 'oops')),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('renders items and share button once loaded', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        SplitLoaded(
          session: _session,
          perPersonMinor: const <String, int>{},
        ),
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('split.item.1')), findsOneWidget);
      expect(find.byKey(const Key('split.share')), findsOneWidget);
    });

    testWidgets('renders without overflow across locales and theme modes', (
      WidgetTester tester,
    ) async {
      when(() => bloc.state).thenReturn(
        SplitLoaded(
          session: _session,
          perPersonMinor: const <String, int>{},
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
