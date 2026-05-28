// Initializing formals make the constructor harder to read when we also
// need to default-resolve `_now`; keep the explicit field bindings.
// ignore_for_file: prefer_initializing_formals

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/features/expenses/domain/usecases/usecase.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';

/// Lead time for the warranty-expiry reminder.
const Duration kWarrantyReminderLead = Duration(days: 30);

/// Patches the warranty end date on a receipt and (re)schedules the
/// local "warranty expires soon" notification 30 days before [endDate]
/// (Sprint 7).
///
/// Passing a `null` [endDate] clears the warranty and cancels any
/// pending reminder for that receipt. When the computed reminder time
/// is already in the past (warranty < 30 days from now, or already
/// expired) the use case still writes the value but **skips** the
/// schedule — there's no point firing a notification for a date that
/// has already passed.
///
/// Composes:
///   1. `ReceiptArchiveRepository.setWarrantyEndDate` (Drift write)
///   2. `NotificationService.cancel(warrantyNotificationId)` (idempotent)
///   3. `NotificationService.scheduleWarrantyReminder` when in horizon.
class AddWarrantyUseCase implements UseCase<void, AddWarrantyParams> {
  AddWarrantyUseCase({
    required ReceiptArchiveRepository repository,
    required NotificationService notifications,
    String reminderTitle = 'Garanti süresi yaklaşıyor',
    String Function(String store, DateTime endDate)? reminderBodyBuilder,
    DateTime Function()? now,
  })  : _repository = repository,
        _notifications = notifications,
        _reminderTitle = reminderTitle,
        _reminderBodyBuilder = reminderBodyBuilder,
        _now = now ?? DateTime.now;

  final ReceiptArchiveRepository _repository;
  final NotificationService _notifications;
  final String _reminderTitle;
  final String Function(String store, DateTime endDate)? _reminderBodyBuilder;
  final DateTime Function() _now;

  @override
  Future<Either<Failure, void>> call(AddWarrantyParams params) async {
    final Either<Failure, void> write = await _repository.setWarrantyEndDate(
      params.receiptId,
      params.endDate,
    );
    if (write.isLeft()) {
      return write;
    }
    // Always cancel first — re-scheduling with the same id replaces, but
    // a `null` endDate must still cancel the previous reminder.
    final int notifId =
        _notifications.warrantyNotificationId(params.receiptId);
    await _notifications.cancel(notifId);

    if (params.endDate == null) {
      return const Right<Failure, void>(null);
    }
    final DateTime fireAt = params.endDate!.subtract(kWarrantyReminderLead);
    if (!fireAt.isAfter(_now())) {
      // Reminder is in the past — write succeeded, just don't schedule.
      return const Right<Failure, void>(null);
    }
    final String body = _reminderBodyBuilder?.call(
          params.storeName ?? '',
          params.endDate!,
        ) ??
        _defaultBody(params.storeName, params.endDate!);
    await _notifications.scheduleWarrantyReminder(
      id: notifId,
      title: _reminderTitle,
      body: body,
      when: fireAt,
    );
    return const Right<Failure, void>(null);
  }

  String _defaultBody(String? store, DateTime endDate) {
    final String label = (store == null || store.isEmpty) ? 'Fiş' : store;
    final String date =
        '${endDate.day.toString().padLeft(2, '0')}.'
        '${endDate.month.toString().padLeft(2, '0')}.'
        '${endDate.year}';
    return '$label garantisi $date tarihinde sona eriyor.';
  }
}

class AddWarrantyParams extends Equatable {
  const AddWarrantyParams({
    required this.receiptId,
    required this.endDate,
    this.storeName,
  });

  final int receiptId;

  /// Pass `null` to clear the warranty and cancel any scheduled
  /// reminder.
  final DateTime? endDate;

  /// Used to build a friendlier reminder body when present.
  final String? storeName;

  @override
  List<Object?> get props => <Object?>[receiptId, endDate, storeName];
}
