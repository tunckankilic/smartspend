import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartspend/core/database/app_database.dart' as drift_db;
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/core/services/recurring_expense_scheduler.dart';
import 'package:smartspend/features/expenses/domain/entities/recurring_period.dart';

import '../../helpers/test_database.dart';

class _MockNotifications extends Mock implements NotificationService {}

void main() {
  // ---------------------------------------------------------------------
  // Pure helpers
  // ---------------------------------------------------------------------

  group('occurrencesElapsed', () {
    test('weekly counts full 7-day spans only', () {
      expect(
        occurrencesElapsed(
          period: RecurringPeriod.weekly,
          anchorUtc: DateTime.utc(2026, 5, 1),
          nowUtc: DateTime.utc(2026, 5, 14),
        ),
        1, // 13 days → 1 full week
      );
      expect(
        occurrencesElapsed(
          period: RecurringPeriod.weekly,
          anchorUtc: DateTime.utc(2026, 5, 1),
          nowUtc: DateTime.utc(2026, 5, 22),
        ),
        3,
      );
    });

    test('monthly counts calendar-month anchors with day underflow', () {
      // Anchor: Jan 31. Now: Mar 30 → 1 occurrence (Feb 28 anchor passed,
      // Mar 31 anchor not yet because today is the 30th).
      expect(
        occurrencesElapsed(
          period: RecurringPeriod.monthly,
          anchorUtc: DateTime.utc(2026, 1, 31),
          nowUtc: DateTime.utc(2026, 3, 30),
        ),
        1,
      );
      // Apr 30 anchor (clamped from 31) not yet reached on Apr 5.
      expect(
        occurrencesElapsed(
          period: RecurringPeriod.monthly,
          anchorUtc: DateTime.utc(2026, 1, 31),
          nowUtc: DateTime.utc(2026, 4, 5),
        ),
        2,
      );
    });

    test('yearly counts whole years with month/day underflow', () {
      expect(
        occurrencesElapsed(
          period: RecurringPeriod.yearly,
          anchorUtc: DateTime.utc(2024, 6, 1),
          nowUtc: DateTime.utc(2026, 5, 30),
        ),
        1,
      );
    });

    test('returns 0 when now precedes anchor', () {
      expect(
        occurrencesElapsed(
          period: RecurringPeriod.weekly,
          anchorUtc: DateTime.utc(2026, 6, 1),
          nowUtc: DateTime.utc(2026, 5, 1),
        ),
        0,
      );
    });
  });

  group('occurrenceDate', () {
    test('monthly clamps day 31 in shorter months', () {
      expect(
        occurrenceDate(
          period: RecurringPeriod.monthly,
          anchorUtc: DateTime.utc(2026, 1, 31),
          seq: 1,
        ),
        DateTime.utc(2026, 2, 28),
      );
    });

    test('yearly clamps Feb 29 in non-leap years', () {
      expect(
        occurrenceDate(
          period: RecurringPeriod.yearly,
          anchorUtc: DateTime.utc(2024, 2, 29),
          seq: 1,
        ),
        DateTime.utc(2025, 2, 28),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Scheduler integration (with in-memory Drift + mock notifications)
  // ---------------------------------------------------------------------

  group('RecurringExpenseSchedulerImpl.tick', () {
    late drift_db.AppDatabase db;
    late SharedPreferences prefs;
    late _MockNotifications notifications;
    late int marketCategoryId;

    setUp(() async {
      db = createTestDatabase();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      notifications = _MockNotifications();
      when(
        () => notifications.recurringNotificationId(any()),
      ).thenAnswer((Invocation i) => 2000 + (i.positionalArguments[0] as int));
      when(
        () => notifications.scheduleRecurringReminder(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          when: any(named: 'when'),
        ),
      ).thenAnswer((_) async {});

      final List<drift_db.Category> defaults =
          await db.categoryDao.getDefaults();
      marketCategoryId = defaults
          .firstWhere((drift_db.Category c) => c.name == 'Market')
          .id;
    });

    tearDown(() async => db.close());

    Future<int> seedRecurring({
      required DateTime anchor,
      required RecurringPeriod period,
      String? note = 'Netflix',
    }) async {
      final DateTime now = DateTime.now().toUtc();
      return db.expenseDao.insertExpense(
        drift_db.ExpensesCompanion.insert(
          amount: 12000,
          categoryId: marketCategoryId,
          date: anchor,
          isRecurring: const Value<bool>(true),
          recurringPeriod: Value<String?>(period.name),
          note: Value<String?>(note),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    RecurringExpenseSchedulerImpl build(DateTime fakeNow) {
      return RecurringExpenseSchedulerImpl(
        expenseDao: db.expenseDao,
        notifications: notifications,
        prefs: prefs,
        logger: Logger(level: Level.warning),
        now: () => fakeNow,
      );
    }

    test('materialises missing weekly occurrences', () async {
      await seedRecurring(
        anchor: DateTime.utc(2026, 5, 1),
        period: RecurringPeriod.weekly,
      );
      final RecurringExpenseSchedulerImpl s =
          build(DateTime.utc(2026, 5, 22));
      final int inserted = await s.tick();
      expect(inserted, 3); // 3 elapsed weekly occurrences after anchor.
    });

    test('is idempotent across consecutive ticks (within throttle)', () async {
      await seedRecurring(
        anchor: DateTime.utc(2026, 5, 1),
        period: RecurringPeriod.weekly,
      );
      final DateTime t1 = DateTime.utc(2026, 5, 22, 9);
      final RecurringExpenseSchedulerImpl s1 = build(t1);
      expect(await s1.tick(), 3);

      // Second tick 1 hour later — throttled out, no inserts.
      final RecurringExpenseSchedulerImpl s2 =
          build(t1.add(const Duration(hours: 1)));
      expect(await s2.tick(), 0);
    });

    test('schedules a reminder for the next upcoming occurrence', () async {
      await seedRecurring(
        anchor: DateTime.utc(2026, 5, 1),
        period: RecurringPeriod.weekly,
      );
      // 2 days before the next weekly anchor (May 29) → reminder
      // scheduled for May 28.
      final RecurringExpenseSchedulerImpl s =
          build(DateTime.utc(2026, 5, 27));
      await s.tick();
      verify(
        () => notifications.scheduleRecurringReminder(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          when: DateTime.utc(2026, 5, 28),
        ),
      ).called(1);
    });

    test('skips rows whose recurring_period is null or unrecognised',
        () async {
      final DateTime now = DateTime.now().toUtc();
      await db.expenseDao.insertExpense(
        drift_db.ExpensesCompanion.insert(
          amount: 1000,
          categoryId: marketCategoryId,
          date: DateTime.utc(2026, 5, 1),
          isRecurring: const Value<bool>(true),
          recurringPeriod: const Value<String?>('biennial'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final RecurringExpenseSchedulerImpl s =
          build(DateTime.utc(2026, 6, 1));
      expect(await s.tick(), 0);
    });
  });
}
