import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/app/bloc/app_bloc.dart';
import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/auth/domain/entities/app_user.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/settings/domain/entities/export_result.dart';
import 'package:smartspend/features/settings/domain/entities/user_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/export_data.dart';
import 'package:smartspend/features/settings/domain/usecases/get_preferences.dart';
import 'package:smartspend/features/settings/domain/usecases/set_ai_consent.dart';
import 'package:smartspend/features/settings/domain/usecases/set_currency.dart';
import 'package:smartspend/features/settings/domain/usecases/set_notifications_enabled.dart';
import 'package:smartspend/features/settings/presentation/bloc/export_cubit.dart';
import 'package:smartspend/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smartspend/features/settings/presentation/pages/settings_page.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

class _MockGetPreferences extends Mock implements GetPreferencesUseCase {}

class _MockSetCurrency extends Mock implements SetCurrencyUseCase {}

class _MockSetNotifications extends Mock
    implements SetNotificationsEnabledUseCase {}

class _MockSetAiConsent extends Mock implements SetAiConsentUseCase {}

class _MockExportData extends Mock implements ExportDataUseCase {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

void main() {
  late _MockGetPreferences getPreferences;
  late _MockSetCurrency setCurrency;
  late _MockSetNotifications setNotifications;
  late _MockSetAiConsent setAiConsent;
  late _MockExportData exportData;
  late _MockAuthBloc authBloc;
  late _MockSyncCubit syncCubit;
  late AppBloc appBloc;

  const AppUser user = AppUser(
    id: 'u1',
    email: 'jane@example.com',
    displayName: 'Jane Doe',
  );

  setUpAll(() {
    registerFallbackValue(const NoParams());
    registerFallbackValue(const ExportParams());
    registerFallbackValue(const AppThemeModeChanged(ThemeMode.dark));
  });

  setUp(() {
    getPreferences = _MockGetPreferences();
    setCurrency = _MockSetCurrency();
    setNotifications = _MockSetNotifications();
    setAiConsent = _MockSetAiConsent();
    exportData = _MockExportData();
    authBloc = _MockAuthBloc();
    syncCubit = _MockSyncCubit();
    appBloc = AppBloc();

    when(() => getPreferences(any())).thenAnswer(
      (_) async =>
          const Right<Failure, UserPreferences>(UserPreferences.defaults),
    );
    when(() => authBloc.state).thenReturn(const Authenticated(user: user));
    when(() => syncCubit.state).thenReturn(const SyncIdle());

    sl
      ..registerFactory<SettingsCubit>(
        () => SettingsCubit(
          getPreferences: getPreferences,
          setCurrency: setCurrency,
          setNotifications: setNotifications,
          setAiConsentUseCase: setAiConsent,
        ),
      )
      ..registerFactory<ExportCubit>(
        () => ExportCubit(exportData: exportData),
      );
  });

  tearDown(() async {
    await sl.reset();
    await authBloc.close();
    await syncCubit.close();
    await appBloc.close();
  });

  Widget wrap() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<AppBloc>.value(value: appBloc),
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<SyncCubit>.value(value: syncCubit),
        ],
        child: const SettingsPage(),
      ),
    );
  }

  /// The preferences column grew past the default 800x600 test surface —
  /// give tap-based tests a taller viewport so ensureVisible + tap land.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders the account, preferences and data tiles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('jane@example.com'), findsOneWidget);
    // Initial placeholder avatar (no avatar bucket).
    expect(find.text('J'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    // Notifications + AI consent + dark mode.
    expect(find.byType(SwitchListTile), findsNWidgets(3));
  });

  testWidgets('toggles dark mode through AppBloc', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(appBloc.state.themeMode, ThemeMode.system);
    await tester.ensureVisible(find.byType(Switch).last);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    expect(appBloc.state.themeMode, ThemeMode.dark);
  });

  testWidgets('grants AI consent through the settings toggle', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    when(
      () => setAiConsent(any()),
    ).thenAnswer((_) async => const Right<Failure, Unit>(unit));
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final Finder tile = find.widgetWithText(
      SwitchListTile,
      'AI-enhanced scanning',
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();

    verify(() => setAiConsent(true)).called(1);
  });

  testWidgets('requests an export when "download my data" is tapped', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    when(() => exportData(any())).thenAnswer(
      (_) async =>
          const Left<Failure, ExportResult>(ServerFailure(message: 'x')),
    );
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final Finder tile = find.widgetWithText(ListTile, 'Download my data');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();

    verify(() => exportData(any())).called(1);
  });

  testWidgets('requests a PDF export when "Download PDF report" is tapped', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    when(() => exportData(any())).thenAnswer(
      (_) async =>
          const Left<Failure, ExportResult>(ServerFailure(message: 'x')),
    );
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final Finder tile = find.widgetWithText(ListTile, 'Download PDF report');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();

    final ExportParams captured =
        verify(() => exportData(captureAny())).captured.single as ExportParams;
    expect(captured.format, ExportFormat.pdf);
  });
}
