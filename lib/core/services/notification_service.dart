// coverage:ignore-file
// flutter_local_notifications platform-channel wrapper; not unit-testable
// without a device/plugin harness.
/// Local notification surface for SmartSpend (Sprint 6).
///
/// Wraps the `flutter_local_notifications` plugin behind an interface so
/// BLoCs depend on a swappable contract and tests can supply a mock. The
/// service is purely **local** — no FCM/APNs in this project. A
/// server-driven channel may arrive in a later sprint via Supabase Edge
/// Functions + a `notifications_outbox` table.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Channel identifiers — kept here so callers never hand-write a string.
///
/// Android groups notifications by channel; iOS ignores the field but
/// still benefits from the categorical separation when we later add
/// per-category mute toggles in Settings.
class NotificationChannel {
  const NotificationChannel._();

  /// Budget threshold crossings (%80, %100). High importance — the user
  /// asked for this and missing it defeats the feature.
  static const String budgetAlerts = 'budget_alerts';

  /// Weekly summary push (Sunday morning by default). Medium importance.
  static const String weeklySummary = 'weekly_summary';

  /// Recurring expense reminders ("Netflix yarın çekilecek"). Medium.
  static const String recurringReminders = 'recurring_reminders';

  /// Warranty expiry reminders for archived receipts (Sprint 7). Medium —
  /// the user benefits but missing one isn't catastrophic.
  static const String warrantyReminders = 'warranty_reminders';

  /// Tax and payment deadline reminders (1.3.0, Block 4). Its own channel so
  /// a user can mute subscription nudges without muting the one notification
  /// class that has a legal deadline behind it.
  static const String taxReminders = 'tax_reminders';
}

/// Stable id offsets per channel so cancellations target the right row
/// without bookkeeping the full id<->payload map.
class _NotificationIdSpace {
  const _NotificationIdSpace._();
  static const int budgetBase = 1000;
  static const int recurringBase = 2000;
  static const int warrantyBase = 3000;
  static const int weeklySummary = 30001;

  /// Tax reminders get their own decade, well clear of every other space.
  ///
  /// One obligation needs six slots (two deadlines × three lead times), so
  /// ids run `taxBase + itemId * 6 + step * 3 + lead`. The range is stated
  /// explicitly because the scheduler cancels by range: it replaces the whole
  /// tax plan on every tick rather than tracking which ids it wrote last time,
  /// and a stale reminder for a deadline the user has since filed is exactly
  /// the notification that makes someone turn notifications off.
  static const int taxBase = 100000;
  static const int taxEnd = 1000000;
}

/// Lowest id a tax reminder can occupy. Exposed so the scheduler can sweep
/// the range without knowing the arithmetic.
const int kTaxNotificationIdStart = _NotificationIdSpace.taxBase;

/// One past the highest. Fits roughly 150 000 obligations, against a calendar
/// that generates on the order of a hundred.
const int kTaxNotificationIdEnd = _NotificationIdSpace.taxEnd;

/// Public API used by BLoCs and core services.
abstract class NotificationService {
  /// Initialises platform plugins (channels, timezone DB). Safe to call
  /// more than once — implementations should be idempotent.
  Future<void> initialize();

  /// Prompts the user for permission. iOS shows the system dialog; on
  /// Android 13+ this triggers `POST_NOTIFICATIONS`. Returns whether
  /// the user granted permission.
  Future<bool> requestPermissions();

  /// Reflects the current permission state without prompting. `false`
  /// when the user has denied permission OR has not been asked yet.
  Future<bool> hasPermission();

  /// Fires an immediate budget warning. `percentSpent` is informational —
  /// the actual id is derived from [budgetId] so re-firing the same
  /// threshold replaces the previous notification.
  Future<void> showBudgetWarning({
    required int budgetId,
    required int percentSpent,
    required String title,
    required String body,
  });

  /// Fires the weekly summary immediately. The actual scheduling
  /// (Sunday 09:00) lives in [RecurringExpenseScheduler] / a future
  /// server-side cron.
  Future<void> showWeeklySummary({
    required String title,
    required String body,
  });

  /// Schedules a recurring-expense reminder at [when] (UTC).
  ///
  /// [id] should be stable per-source — passing the same id replaces
  /// any previously scheduled notification with that id.
  Future<void> scheduleRecurringReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  });

  /// Schedules a warranty expiry reminder at [when] (UTC), typically 30
  /// days before the warranty end date (Sprint 7). Mechanics are
  /// identical to [scheduleRecurringReminder] — only the channel + id
  /// namespace differ so the user can mute warranty alerts without
  /// silencing subscription reminders.
  Future<void> scheduleWarrantyReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  });

  /// Schedules a tax deadline reminder at [when] (an absolute UTC instant).
  ///
  /// 🚨 [when] is already resolved against the *market's* timezone by
  /// `planTaxReminders`. Nothing here re-interprets it, and in particular
  /// nothing consults `tz.local`: a filing deadline is "the 26th in Turkey"
  /// for a user in Berlin just as much as for one in Ankara.
  ///
  /// [payload] identifies the obligation so a tap can open it.
  Future<void> scheduleTaxReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
  });

  /// Ids of everything currently scheduled and not yet delivered.
  ///
  /// The tax scheduler uses this to clear its own range before re-planning,
  /// which is what lets the plan be recomputed from scratch rather than
  /// diffed against bookkeeping that can drift out of step with reality.
  Future<List<int>> pendingIds();

  /// Payloads of notifications the user tapped, while the app was running.
  ///
  /// A broadcast stream: more than one listener is legitimate (routing and
  /// telemetry are different concerns and neither should have to call the
  /// other).
  Stream<String> get selections;

  /// The payload that cold-started the app, consumed once.
  ///
  /// Separate from [selections] because a tap that launches the process
  /// happens before anything can subscribe. Returns null on an ordinary
  /// launch, and null on every call after the first — it is a handoff, not a
  /// state.
  String? takeLaunchPayload();

  /// Cancels a previously scheduled notification by id.
  Future<void> cancel(int id);

  /// Cancels everything. Used on sign-out (Sprint 8) and in tests.
  Future<void> cancelAll();

  /// Stable id derivation so BLoCs can target the same notification on
  /// repeat threshold crossings.
  int budgetNotificationId(int budgetId) =>
      _NotificationIdSpace.budgetBase + budgetId;

  /// Stable id derivation for recurring expense reminders.
  int recurringNotificationId(int expenseId) =>
      _NotificationIdSpace.recurringBase + expenseId;

  /// Stable id derivation for warranty reminders (Sprint 7). One slot
  /// per receipt so re-saving the same warranty replaces the previous
  /// scheduled notification.
  int warrantyNotificationId(int receiptId) =>
      _NotificationIdSpace.warrantyBase + receiptId;

  /// Stable id for one reminder: one obligation, one deadline, one lead time.
  ///
  /// Derived rather than allocated so the same reminder always lands in the
  /// same slot — re-running the plan replaces the notification instead of
  /// stacking a second copy of it on the lock screen.
  int taxNotificationId({
    required int itemId,
    required int stepIndex,
    required int leadIndex,
  }) =>
      _NotificationIdSpace.taxBase + itemId * 6 + stepIndex * 3 + leadIndex;
}

/// Production implementation backed by `flutter_local_notifications`.
class FlutterLocalNotificationService implements NotificationService {
  FlutterLocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;
  final StreamController<String> _selections =
      StreamController<String>.broadcast();
  String? _launchPayload;

  @override
  Future<void> initialize() async {
    if (_initialised) {
      return;
    }
    tz_data.initializeTimeZones();

    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const InitializationSettings settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _selections.add(payload);
        }
      },
    );

    // A tap that cold-starts the process happens before anything can be
    // listening, so it arrives here instead of on the stream. Held rather
    // than dropped: otherwise a notification only ever works on an app that
    // was already open, which is the less common case.
    final NotificationAppLaunchDetails? launch =
        await _plugin.getNotificationAppLaunchDetails();
    if (launch != null && launch.didNotificationLaunchApp) {
      final String? payload = launch.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _launchPayload = payload;
      }
    }
    _initialised = true;
  }

  @override
  Future<bool> requestPermissions() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final IOSFlutterLocalNotificationsPlugin? ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final bool? granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final bool? granted = await android?.requestNotificationsPermission();
      return granted ?? true; // Android <13 implicitly grants.
    }
    return true;
  }

  @override
  Future<bool> hasPermission() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final IOSFlutterLocalNotificationsPlugin? ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final NotificationsEnabledOptions? options = await ios
          ?.checkPermissions();
      return options?.isEnabled ?? false;
    }
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final bool? granted = await android?.areNotificationsEnabled();
      return granted ?? false;
    }
    return true;
  }

  @override
  Future<void> showBudgetWarning({
    required int budgetId,
    required int percentSpent,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: budgetNotificationId(budgetId),
      title: title,
      body: body,
      notificationDetails: _details(
        channelId: NotificationChannel.budgetAlerts,
        channelName: 'Budget alerts',
        importance: Importance.high,
      ),
      payload: 'budget:$budgetId:$percentSpent',
    );
  }

  @override
  Future<void> showWeeklySummary({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: _NotificationIdSpace.weeklySummary,
      title: title,
      body: body,
      notificationDetails: _details(
        channelId: NotificationChannel.weeklySummary,
        channelName: 'Weekly summary',
      ),
      payload: 'weekly_summary',
    );
  }

  @override
  Future<void> scheduleRecurringReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final tz.TZDateTime scheduled = tz.TZDateTime.from(when.toUtc(), tz.UTC);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details(
        channelId: NotificationChannel.recurringReminders,
        channelName: 'Recurring reminders',
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Required by the iOS<10 fallback path. We're iOS16+ minimum (see
      // CLAUDE.md), so wall-clock interpretation is the right pick.
      payload: 'recurring:$id',
    );
  }

  @override
  Future<void> scheduleWarrantyReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final tz.TZDateTime scheduled = tz.TZDateTime.from(when.toUtc(), tz.UTC);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details(
        channelId: NotificationChannel.warrantyReminders,
        channelName: 'Warranty reminders',
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,

      payload: 'warranty:$id',
    );
  }

  @override
  Future<void> scheduleTaxReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
  }) async {
    // tz.UTC, not tz.local: `when` is already an absolute instant that the
    // planner resolved in the market's zone. Re-reading the device zone here
    // would move the reminder for exactly the users it is most likely to be
    // wrong for — the ones abroad.
    final tz.TZDateTime scheduled = tz.TZDateTime.from(when.toUtc(), tz.UTC);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details(
        channelId: NotificationChannel.taxReminders,
        channelName: 'Tax reminders',
        importance: Importance.high,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<List<int>> pendingIds() async {
    final List<PendingNotificationRequest> pending =
        await _plugin.pendingNotificationRequests();
    return pending
        .map((PendingNotificationRequest r) => r.id)
        .toList(growable: false);
  }

  @override
  Stream<String> get selections => _selections.stream;

  @override
  String? takeLaunchPayload() {
    final String? payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  int budgetNotificationId(int budgetId) =>
      _NotificationIdSpace.budgetBase + budgetId;

  @override
  int recurringNotificationId(int expenseId) =>
      _NotificationIdSpace.recurringBase + expenseId;

  @override
  int warrantyNotificationId(int receiptId) =>
      _NotificationIdSpace.warrantyBase + receiptId;

  @override
  int taxNotificationId({
    required int itemId,
    required int stepIndex,
    required int leadIndex,
  }) =>
      _NotificationIdSpace.taxBase + itemId * 6 + stepIndex * 3 + leadIndex;

  NotificationDetails _details({
    required String channelId,
    required String channelName,
    Importance importance = Importance.defaultImportance,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: importance,
        priority: importance == Importance.high
            ? Priority.high
            : Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }
}
