import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/app/bloc/app_bloc.dart';
import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/app/locale_resolution.dart';
import 'package:smartspend/app/router.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/core/services/onboarding_flag_store.dart';
import 'package:smartspend/core/services/telemetry_service.dart';
import 'package:smartspend/core/theme/app_theme.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';
import 'package:smartspend/l10n/generated/app_localizations.dart';

/// Root widget for SmartSpend.
///
/// Owns the top-level [MultiBlocProvider]: [AppBloc] for theme/locale and
/// [AuthBloc] for session state. [GoRouter] receives `AuthBloc` to drive
/// redirect logic, and the whole tree rebuilds on theme/locale changes.
class SmartSpendApp extends StatefulWidget {
  const SmartSpendApp({super.key});

  @override
  State<SmartSpendApp> createState() => _SmartSpendAppState();
}

class _SmartSpendAppState extends State<SmartSpendApp> {
  late final AuthBloc _authBloc;
  late final AppBloc _appBloc;
  late final SyncCubit _syncCubit;
  late final GoRouter _router;
  StreamSubscription<String>? _notificationTaps;

  @override
  void initState() {
    super.initState();
    _appBloc = sl<AppBloc>();
    _syncCubit = sl<SyncCubit>();
    _authBloc = sl<AuthBloc>()..add(const AuthCheckRequested());
    _router = buildRouter(
      authBloc: _authBloc,
      onboardingFlagStore: sl<OnboardingFlagStore>(),
    );

    final NotificationService notifications = sl<NotificationService>();
    _notificationTaps = notifications.selections.listen(_openFromNotification);
    // A tap that cold-started the process arrives here rather than on the
    // stream — nothing was listening when it happened. Deferred by a frame so
    // the router is mounted before it is asked to navigate.
    final String? launch = notifications.takeLaunchPayload();
    if (launch != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openFromNotification(launch),
      );
    }
  }

  /// Routes a tapped notification, and records that it was tapped.
  ///
  /// The telemetry matters as much as the navigation: `tax_notification_opened`
  /// is the only signal we get on whether these reminders are wanted at all,
  /// and a reminder nobody opens is one to stop sending rather than one to
  /// send more of.
  ///
  /// ⚠️ It is a bare count, not a rate — nothing counts how many were
  /// *scheduled*, so it cannot answer "what fraction get opened". Reading it
  /// as one would overstate what it knows.
  void _openFromNotification(String payload) {
    if (!payload.startsWith('tax:')) {
      return;
    }
    final int? itemId = int.tryParse(payload.substring(4));
    if (itemId == null) {
      return;
    }
    unawaited(
      sl<TelemetryService>().record(ProductEvent.taxNotificationOpened),
    );
    _router.go('/taxes/$itemId');
  }

  @override
  void dispose() {
    unawaited(_notificationTaps?.cancel());
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<Object?>>[
        BlocProvider<AppBloc>.value(value: _appBloc),
        BlocProvider<AuthBloc>.value(value: _authBloc),
        BlocProvider<SyncCubit>.value(value: _syncCubit),
      ],
      child: BlocBuilder<AppBloc, AppState>(
        builder: (BuildContext context, AppState state) {
          return MaterialApp.router(
            title: 'SmartSpend',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            locale: state.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            // Follow the device language when it is one we ship (tr/de/en);
            // otherwise fall back to English. Shared with the boot-time
            // schedulers, which need the same answer without a BuildContext.
            localeResolutionCallback: resolveAppLocale,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
