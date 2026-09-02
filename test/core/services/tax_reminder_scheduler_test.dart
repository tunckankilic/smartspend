import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/database/app_database.dart';
import 'package:smartspend/core/market/market_registry.dart';
import 'package:smartspend/core/market/tax/tax_calendar_generator.dart';
import 'package:smartspend/core/market/tax/tax_obligation_kind.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/tax_period.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/core/services/tax_reminder_scheduler.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';

import '../../helpers/test_database.dart';

class _MockTaxRepository extends Mock implements TaxRepository {}

/// Records what was scheduled instead of talking to a platform channel.
///
/// Hand-rolled rather than mocked so that [taxNotificationId] runs its real
/// arithmetic — the id is what decides whether a re-plan replaces a reminder
/// or stacks a second copy of it, and a stubbed id would test nothing.
class _RecordingNotifications implements NotificationService {
  final Map<int, String> scheduled = <int, String>{};
  final List<int> cancelled = <int>[];
  List<int> pending = <int>[];
  bool permitted = true;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> scheduleTaxReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
  }) async {
    scheduled[id] = '$title|$body|${when.toIso8601String()}|$payload';
  }

  @override
  Future<List<int>> pendingIds() async => pending;

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  int taxNotificationId({
    required int itemId,
    required int stepIndex,
    required int leadIndex,
  }) =>
      kTaxNotificationIdStart + itemId * 6 + stepIndex * 3 + leadIndex;

  // Everything below is out of this suite's scope.
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<void> showBudgetWarning({
    required int budgetId,
    required int percentSpent,
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> showWeeklySummary({
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> scheduleRecurringReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {}
  @override
  Future<void> scheduleWarrantyReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {}
  @override
  Stream<String> get selections => const Stream<String>.empty();
  @override
  String? takeLaunchPayload() => null;
  @override
  Future<void> cancelAll() async {}
  @override
  int budgetNotificationId(int budgetId) => budgetId;
  @override
  int recurringNotificationId(int expenseId) => expenseId;
  @override
  int warrantyNotificationId(int receiptId) => receiptId;
}

void main() {
  late AppDatabase db;
  late _MockTaxRepository repository;
  late _RecordingNotifications notifications;
  late TaxReminderScheduler scheduler;

  DateTime now() => DateTime.utc(2026, 9, 1, 10);

  TaxCalendarItem item({
    int id = 1,
    DateTime? paymentDue,
    int? amountMinor,
    TaxAmountSource amountSource = TaxAmountSource.unknown,
  }) =>
      TaxCalendarItem(
        id: id,
        kind: TaxObligationKind.kdv1,
        nameL10nKey: TaxObligationKind.kdv1.l10nKey,
        periodKind: TaxPeriodKind.monthly,
        periodStart: DateTime.utc(2026, 9),
        periodEnd: DateTime.utc(2026, 9, 30),
        installmentIndex: 0,
        dueDateSource: TaxDueDateSource.catalog,
        amountSource: amountSource,
        amountMinor: amountMinor,
        hasDeclarationStep: false,
        hasPaymentStep: true,
        isConditional: false,
        needsDateWarning: true,
        isUserDefined: false,
        paymentDueDate: paymentDue,
      );

  void withItems(List<TaxCalendarItem> items) {
    when(() => repository.watchCalendar()).thenAnswer(
      (_) => Stream<TaxCalendarSnapshot>.value(
        TaxCalendarSnapshot(
          items: items,
          gaps: const <TaxCalendarGap>[],
          profile: TaxpayerProfile.empty,
        ),
      ),
    );
  }

  setUp(() {
    db = createTestDatabase();
    repository = _MockTaxRepository();
    notifications = _RecordingNotifications();
    scheduler = TaxReminderSchedulerImpl(
      repository: repository,
      notifications: notifications,
      markets: MarketRegistry(),
      settingsDao: db.userSettingsDao,
      clock: now,
    );
    withItems(<TaxCalendarItem>[
      item(paymentDue: DateTime.utc(2026, 9, 26)),
    ]);
  });

  tearDown(() async => db.close());

  test('should schedule one notification per planned reminder', () async {
    final int count = await scheduler.tick(languageCode: 'tr');

    expect(count, 3);
    expect(notifications.scheduled, hasLength(3));
  });

  test('should say nothing when the user has denied notifications', () async {
    // Scheduling into a denied permission writes reminders nobody sees and
    // then reports success.
    notifications.permitted = false;

    expect(await scheduler.tick(languageCode: 'tr'), 0);
    expect(notifications.scheduled, isEmpty);
  });

  test('should not reschedule an unchanged plan', () async {
    await scheduler.tick(languageCode: 'tr');
    notifications.scheduled.clear();

    await scheduler.tick(languageCode: 'tr');

    expect(notifications.scheduled, isEmpty);
  });

  test('should reschedule when the app language changes', () async {
    await scheduler.tick(languageCode: 'tr');
    notifications.scheduled.clear();

    // Same deadlines, different notifications. A user who switched to English
    // should stop receiving Turkish ones.
    await scheduler.tick(languageCode: 'en');

    expect(notifications.scheduled, hasLength(3));
  });

  test('should clear its own range and leave other channels alone', () async {
    // 🚨 The stale reminder is the one that matters: a nudge to file a return
    // the user filed last week is what gets notifications switched off. The
    // sweep is by id range, so it must not take the budget alert with it.
    const int foreignId = 1042;
    final int ours = notifications.taxNotificationId(
      itemId: 99,
      stepIndex: 0,
      leadIndex: 0,
    );
    notifications.pending = <int>[foreignId, ours];

    await scheduler.tick(languageCode: 'tr');

    expect(notifications.cancelled, contains(ours));
    expect(notifications.cancelled, isNot(contains(foreignId)));
  });

  test('should carry the obligation in the payload so a tap can open it',
      () async {
    await scheduler.tick(languageCode: 'tr');

    expect(
      notifications.scheduled.values.every((String s) => s.endsWith('tax:1')),
      isTrue,
    );
  });

  test('should schedule again after a sign-out cleared the device', () async {
    await scheduler.tick(languageCode: 'tr');
    notifications.scheduled.clear();

    // Sign-out cancels the notifications and wipes the account's rows. If the
    // fingerprint survived that, the scheduler would believe its work was
    // already done and the same user signing back in would silently never get
    // their reminders again.
    await db.clearUserData();

    await scheduler.tick(languageCode: 'tr');

    expect(notifications.scheduled, hasLength(3));
  });

  group('the wording', () {
    test('should never state a deadline as fact', () async {
      // Every date in the calendar comes from a rule nobody has verified
      // against GİB. On a lock screen there is no room to qualify it, so the
      // qualification has to be in the sentence.
      await scheduler.tick(languageCode: 'tr');

      expect(
        notifications.scheduled.values.every(
          (String s) =>
              s.contains('Takvimimize göre') && s.contains('teyit et'),
        ),
        isTrue,
      );
    });

    test('should name an amount the accountant gave', () async {
      withItems(<TaxCalendarItem>[
        item(
          paymentDue: DateTime.utc(2026, 9, 26),
          amountMinor: 125000,
          amountSource: TaxAmountSource.accountant,
        ),
      ]);

      await scheduler.tick(languageCode: 'tr');

      expect(
        notifications.scheduled.values.every(
          (String s) => s.contains('1.250'),
        ),
        isTrue,
      );
    });

    test('should withhold an amount the user typed themselves', () async {
      withItems(<TaxCalendarItem>[
        item(
          paymentDue: DateTime.utc(2026, 9, 26),
          amountMinor: 125000,
          amountSource: TaxAmountSource.user,
        ),
      ]);

      await scheduler.tick(languageCode: 'tr');

      expect(
        notifications.scheduled.values.any((String s) => s.contains('1.250')),
        isFalse,
      );
    });
  });
}
