import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/notification_service.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';
import 'package:smartspend/features/receipts/domain/usecases/add_warranty.dart';

class _MockRepo extends Mock implements ReceiptArchiveRepository {}

class _MockNotif extends Mock implements NotificationService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime.utc(2026));
  });

  late _MockRepo repo;
  late _MockNotif notif;

  setUp(() {
    repo = _MockRepo();
    notif = _MockNotif();
    when(() => notif.warrantyNotificationId(any())).thenReturn(3001);
    when(() => notif.cancel(any())).thenAnswer((_) async {});
    when(
      () => notif.scheduleWarrantyReminder(
        id: any<int>(named: 'id'),
        title: any<String>(named: 'title'),
        body: any<String>(named: 'body'),
        when: any<DateTime>(named: 'when'),
      ),
    ).thenAnswer((_) async {});
  });

  AddWarrantyUseCase build({DateTime Function()? now}) => AddWarrantyUseCase(
        repository: repo,
        notifications: notif,
        now: now,
      );

  test('should schedule a reminder 30 days before the warranty ends',
      () async {
    when(() => repo.setWarrantyEndDate(any(), any()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
    final DateTime now = DateTime.utc(2026, 5, 28);
    final DateTime end = DateTime.utc(2027, 5, 28); // +365d
    final AddWarrantyUseCase useCase = build(now: () => now);

    final Either<Failure, void> result = await useCase(
      AddWarrantyParams(receiptId: 1, endDate: end, storeName: 'Migros'),
    );

    expect(result.isRight(), isTrue);
    verify(() => repo.setWarrantyEndDate(1, end)).called(1);
    verify(() => notif.cancel(3001)).called(1);
    final VerificationResult v = verify(
      () => notif.scheduleWarrantyReminder(
        id: 3001,
        title: any<String>(named: 'title'),
        body: any<String>(named: 'body'),
        when: captureAny<DateTime>(named: 'when'),
      ),
    )..called(1);
    final DateTime fireAt = v.captured.single as DateTime;
    expect(fireAt, end.subtract(const Duration(days: 30)));
  });

  test('should cancel the reminder when endDate is null', () async {
    when(() => repo.setWarrantyEndDate(any(), any()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
    final AddWarrantyUseCase useCase = build();

    final Either<Failure, void> result = await useCase(
      const AddWarrantyParams(receiptId: 1, endDate: null),
    );

    expect(result.isRight(), isTrue);
    verify(() => repo.setWarrantyEndDate(1, null)).called(1);
    verify(() => notif.cancel(3001)).called(1);
    verifyNever(
      () => notif.scheduleWarrantyReminder(
        id: any<int>(named: 'id'),
        title: any<String>(named: 'title'),
        body: any<String>(named: 'body'),
        when: any<DateTime>(named: 'when'),
      ),
    );
  });

  test('should skip scheduling when the reminder time is in the past',
      () async {
    when(() => repo.setWarrantyEndDate(any(), any()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
    final DateTime now = DateTime.utc(2026, 5, 28);
    // Warranty ends in 10 days — reminder would be 20 days ago.
    final DateTime end = now.add(const Duration(days: 10));
    final AddWarrantyUseCase useCase = build(now: () => now);

    final Either<Failure, void> result = await useCase(
      AddWarrantyParams(receiptId: 1, endDate: end),
    );

    expect(result.isRight(), isTrue);
    verify(() => notif.cancel(3001)).called(1);
    verifyNever(
      () => notif.scheduleWarrantyReminder(
        id: any<int>(named: 'id'),
        title: any<String>(named: 'title'),
        body: any<String>(named: 'body'),
        when: any<DateTime>(named: 'when'),
      ),
    );
  });

  test('should propagate repository failure without touching notifications',
      () async {
    when(() => repo.setWarrantyEndDate(any(), any())).thenAnswer(
      (_) async => const Left<Failure, void>(CacheFailure(message: 'boom')),
    );
    final AddWarrantyUseCase useCase = build();

    final Either<Failure, void> result = await useCase(
      AddWarrantyParams(
        receiptId: 1,
        endDate: DateTime.utc(2027),
      ),
    );

    expect(result.isLeft(), isTrue);
    verifyNever(() => notif.cancel(any()));
    verifyNever(
      () => notif.scheduleWarrantyReminder(
        id: any<int>(named: 'id'),
        title: any<String>(named: 'title'),
        body: any<String>(named: 'body'),
        when: any<DateTime>(named: 'when'),
      ),
    );
  });
}
