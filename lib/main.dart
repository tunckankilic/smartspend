// Sentry 8.x emits `extra` deprecation hints; Sprint 9 migrates to the
// structured Contexts API. Locally silenced to keep `flutter analyze` clean.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:smartspend/app/app.dart';
import 'package:smartspend/app/bloc_observer.dart';
import 'package:smartspend/app/injection_container.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/core/services/recurring_expense_scheduler.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/core/supabase/supabase_client_provider.dart';

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
        ..beforeSend = _scrubSecrets;
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
      // Drift ⇄ Supabase sync engine (Sprint 8.3). `start` installs the
      // connectivity listener + periodic foreground timer; the initial
      // `sync` is fire-and-forget so a slow network never blocks paint.
      sl<SyncService>().start();
      unawaited(sl<SyncService>().sync());
      Bloc.observer = AppBlocObserver();
      runApp(const SmartSpendApp());
    },
  );
}

/// Strip anything that smells like a secret before Sentry sees it.
///
/// Sentry's docs recommend `sendDefaultPii = false`, but breadcrumbs and
/// extras can still carry tokens added by SDKs. Be paranoid.
FutureOr<SentryEvent?> _scrubSecrets(SentryEvent event, Hint hint) {
  const Set<String> blacklistedKeys = <String>{
    'password',
    'token',
    'access_token',
    'refresh_token',
    'authorization',
    'apikey',
    'api_key',
    'supabase_anon_key',
    'gemini_api_key',
    'jwt',
  };

  bool isSecretKey(String key) {
    final String lower = key.toLowerCase();
    return blacklistedKeys.any(lower.contains);
  }

  Map<String, dynamic> scrubMap(Map<String, dynamic> source) {
    final Map<String, dynamic> result = <String, dynamic>{};
    source.forEach((String key, dynamic value) {
      if (isSecretKey(key)) {
        result[key] = '[Filtered]';
      } else if (value is Map<String, dynamic>) {
        result[key] = scrubMap(value);
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  final Map<String, dynamic>? extra = event.extra;
  final SentryEvent scrubbed = event.copyWith(
    extra: extra == null ? null : scrubMap(extra),
    breadcrumbs: event.breadcrumbs
        ?.map(
          (Breadcrumb b) => b.copyWith(
            data: b.data == null ? null : scrubMap(b.data!),
          ),
        )
        .toList(),
  );

  return scrubbed;
}
