import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:smartspend/app/app.dart';
import 'package:smartspend/app/bloc_observer.dart';
import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/observability/sentry_scrubber.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/core/services/recurring_expense_scheduler.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/supabase/supabase_client_provider.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';

/// Entry point. Order matters:
///   1. Bind Flutter (so plugins are reachable).
///   2. Initialize Sentry first — it captures any failure in step 3+.
///   3. Initialize Supabase — Auth + Postgres + Storage client.
///   4. Wire DI graph.
///   5. Install [AppBlocObserver] so Bloc events feed Sentry breadcrumbs.
///   6. `runApp`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const String sentryDsn = String.fromEnvironment('SENTRY_DSN');
  const String sentryRelease = String.fromEnvironment(
    'SENTRY_RELEASE',
    defaultValue: 'dev',
  );
  const String sentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'development',
  );

  await SentryFlutter.init(
    (SentryFlutterOptions options) {
      options
        ..dsn = sentryDsn
        ..release = sentryRelease
        ..environment = sentryEnvironment
        ..tracesSampleRate = kReleaseMode ? 0.2 : 1.0
        ..attachStacktrace = true
        ..sendDefaultPii = false
        ..beforeSend = scrubSentryEvent;
    },
    appRunner: () async {
      await SupabaseClientProvider.initialize();
      await configureDependencies();
      // Notification plugin needs platform channels — must run after
      // `configureDependencies` so `sl<NotificationService>()` is wired,
      // and before `runApp` so any boot-time scheduler (Sprint 6) can
      // safely enqueue work.
      await sl<NotificationService>().initialize();
      // Foreground recurring-expense materialisation — throttled
      // internally so the call is cheap on warm starts. Fire-and-forget
      // so a slow Drift read doesn't block first paint.
      unawaited(sl<RecurringExpenseScheduler>().tick());
      // Drift ⇄ Supabase sync engine (Sprint 8.3). The service `start`
      // installs the connectivity listener + periodic foreground timer;
      // SyncCubit subscribes to its phase stream so the UI stays in sync.
      // The initial `syncNow` is fire-and-forget so a slow network never
      // blocks paint.
      sl<SyncService>().start();
      sl<SyncCubit>().start();
      unawaited(sl<SyncCubit>().syncNow());
      Bloc.observer = AppBlocObserver();
      runApp(const SmartSpendApp());
    },
  );
}
