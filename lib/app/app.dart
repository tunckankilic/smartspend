import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:smartspend/app/bloc/app_bloc.dart';
import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/app/router.dart';
import 'package:smartspend/core/services/onboarding_flag_store.dart';
import 'package:smartspend/core/theme/app_theme.dart';
import 'package:smartspend/features/auth/presentation/bloc/auth_bloc.dart';
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
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _appBloc = sl<AppBloc>();
    _authBloc = sl<AuthBloc>()..add(const AuthStarted());
    _router = buildRouter(
      authBloc: _authBloc,
      onboardingFlagStore: sl<OnboardingFlagStore>(),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<Object?>>[
        BlocProvider<AppBloc>.value(value: _appBloc),
        BlocProvider<AuthBloc>.value(value: _authBloc),
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
