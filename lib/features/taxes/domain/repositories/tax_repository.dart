import 'package:dartz/dartz.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';

/// Contract for the tax calendar's data access.
///
/// Reads come from Drift unconditionally (offline-first); writes stamp
/// `pending_*` and the sync engine drains them. The generator runs on this
/// side of the boundary: the presentation layer asks for a calendar, not for
/// a profile plus a catalog.
abstract class TaxRepository {
  /// The stored answers, or [TaxpayerProfile.empty] when the wizard has never
  /// been opened. Never null — a missing profile and an unanswered one
  /// generate the same calendar.
  Future<Either<Failure, TaxpayerProfile>> getProfile();

  /// Saves the answers and regenerates the calendar from them.
  ///
  /// Regeneration is part of the save rather than a separate call the caller
  /// could forget: a profile that does not reach the calendar is a profile the
  /// user filled in for nothing.
  Future<Either<Failure, void>> saveProfile(TaxpayerProfile profile);

  /// The calendar, re-emitted whenever an item or the profile changes.
  Stream<TaxCalendarSnapshot> watchCalendar();

  /// Regenerates items for the window the app currently cares about.
  ///
  /// Idempotent: it matches existing items on their generation key and never
  /// touches the marks, note or amount the user put on them.
  Future<Either<Failure, void>> regenerate();

  /// One item, for the detail screen.
  Future<Either<Failure, TaxCalendarItem?>> getItem(int id);

  /// Marks an item filed, or clears the mark when [at] is null.
  Future<Either<Failure, void>> setDeclared(int id, DateTime? at);

  /// Marks an item paid, or clears the mark.
  Future<Either<Failure, void>> setPaid(int id, DateTime? at);

  /// Records that the item does not apply to this taxpayer, or undoes that.
  ///
  /// Kept rather than deleted: it is the clearest signal that the generated
  /// calendar is wrong for them, and a deleted row would be regenerated on the
  /// next run anyway.
  Future<Either<Failure, void>> setDismissed(int id, DateTime? at);

  /// Sets the amount and who said it. There is no source meaning "the app
  /// worked it out".
  Future<Either<Failure, void>> setAmount(
    int id, {
    required int? amountMinor,
    required TaxAmountSource source,
  });

  /// Sets the user's note.
  Future<Either<Failure, void>> setNote(int id, String? note);

  /// Replaces an item's deadlines with the user's own.
  Future<Either<Failure, void>> setUserDueDates(
    int id, {
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
  });

  /// Pulls the server's published deadline corrections and regenerates.
  ///
  /// Best-effort and safe to call on every app launch: it throttles itself,
  /// and failing means the calendar keeps the dates it already had. Offline is
  /// the normal state, not an error condition.
  ///
  /// 🚨 The pull REPLACES this device's overrides rather than merging them,
  /// which is what lets the publisher take a correction back — see D-17. A
  /// merge would leave a withdrawn extension applied forever.
  ///
  /// [force] skips the throttle; the calendar screen's pull-to-refresh uses it.
  Future<Either<Failure, void>> refreshOverrides({bool force});

  /// Adds a deadline the user tracks themselves. Returns the local row id.
  Future<Either<Failure, int>> addCustomItem({
    required String title,
    required DateTime dueDate,
    bool isPayment = true,
    String? note,
  });
}
