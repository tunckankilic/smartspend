import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/market/tax/tax_obligation_record.dart';
import 'package:smartspend/core/market/tax/taxpayer_profile.dart';
import 'package:smartspend/core/services/telemetry_service.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_item.dart';
import 'package:smartspend/features/taxes/domain/entities/tax_calendar_snapshot.dart';
import 'package:smartspend/features/taxes/domain/repositories/tax_repository.dart';
import 'package:smartspend/features/taxes/domain/usecases/add_custom_tax_item.dart';
import 'package:smartspend/features/taxes/domain/usecases/annotate_tax_obligation.dart';
import 'package:smartspend/features/taxes/domain/usecases/mark_tax_obligation.dart';
import 'package:smartspend/features/taxes/domain/usecases/save_tax_profile.dart';

import '../../../../helpers/recording_telemetry_service.dart';

/// Records the calls instead of touching Drift. The assertions here are about
/// which telemetry fires and when, not about persistence.
class _FakeTaxRepository implements TaxRepository {
  TaxpayerProfile? savedProfile;
  final List<String> calls = <String>[];
  Failure? nextFailure;

  Either<Failure, T> _result<T>(T value) {
    final Failure? failure = nextFailure;
    if (failure != null) {
      return Left<Failure, T>(failure);
    }
    return Right<Failure, T>(value);
  }

  @override
  Future<Either<Failure, void>> saveProfile(TaxpayerProfile profile) async {
    calls.add('saveProfile');
    savedProfile = profile;
    return _result<void>(null);
  }

  @override
  Future<Either<Failure, TaxpayerProfile>> getProfile() async =>
      _result<TaxpayerProfile>(savedProfile ?? TaxpayerProfile.empty);

  @override
  Stream<TaxCalendarSnapshot> watchCalendar() =>
      Stream<TaxCalendarSnapshot>.value(TaxCalendarSnapshot.empty);

  @override
  Future<Either<Failure, void>> regenerate() async => _result<void>(null);

  @override
  Future<Either<Failure, TaxCalendarItem?>> getItem(int id) async =>
      _result<TaxCalendarItem?>(null);

  @override
  Future<Either<Failure, void>> setDeclared(int id, DateTime? at) async {
    calls.add('setDeclared');
    return _result<void>(null);
  }

  @override
  Future<Either<Failure, void>> setPaid(int id, DateTime? at) async {
    calls.add('setPaid');
    return _result<void>(null);
  }

  @override
  Future<Either<Failure, void>> setDismissed(int id, DateTime? at) async {
    calls.add('setDismissed');
    return _result<void>(null);
  }

  @override
  Future<Either<Failure, void>> setAmount(
    int id, {
    required int? amountMinor,
    required TaxAmountSource source,
  }) async {
    calls.add('setAmount:${source.wireValue}');
    return _result<void>(null);
  }

  @override
  Future<Either<Failure, void>> setNote(int id, String? note) async {
    calls.add('setNote:$note');
    return _result<void>(null);
  }

  @override
  Future<Either<Failure, void>> setUserDueDates(
    int id, {
    DateTime? declarationDueDate,
    DateTime? paymentDueDate,
  }) async {
    calls.add('setUserDueDates');
    return _result<void>(null);
  }

  @override
  Future<Either<Failure, int>> addCustomItem({
    required String title,
    required DateTime dueDate,
    bool isPayment = true,
    String? note,
  }) async {
    calls.add('addCustomItem:$title');
    return _result<int>(7);
  }
}

void main() {
  late _FakeTaxRepository repository;
  late RecordingTelemetryService telemetry;

  setUp(() {
    repository = _FakeTaxRepository();
    telemetry = RecordingTelemetryService();
  });

  group('SaveTaxProfileUseCase', () {
    test('should count the wizard completion in the D-2 bucket', () async {
      final SaveTaxProfileUseCase useCase = SaveTaxProfileUseCase(
        repository: repository,
        telemetry: telemetry,
      );

      await useCase(
        const SaveTaxProfileParams(
          profile: TaxpayerProfile(legalForm: TaxpayerLegalForm.limited),
          fromWizard: true,
        ),
      );

      expect(telemetry.keys, <String>['tax_profile_completed']);
      expect(
        telemetry.recorded.single.dimension,
        TelemetryDimension.limited,
      );
    });

    test('should count a skipped legal form as an answer', () async {
      // `belirtilmedi` is data about the step, not a missing data point. A
      // high skip rate is itself the finding.
      final SaveTaxProfileUseCase useCase = SaveTaxProfileUseCase(
        repository: repository,
        telemetry: telemetry,
      );

      await useCase(
        const SaveTaxProfileParams(
          profile: TaxpayerProfile.empty,
          fromWizard: true,
        ),
      );

      expect(
        telemetry.recorded.single.dimension,
        TelemetryDimension.belirtilmedi,
      );
    });

    test('should not count a later edit from settings', () async {
      // Counting edits would tilt the distribution towards whoever fiddles
      // with their profile.
      final SaveTaxProfileUseCase useCase = SaveTaxProfileUseCase(
        repository: repository,
        telemetry: telemetry,
      );

      await useCase(
        const SaveTaxProfileParams(
          profile: TaxpayerProfile(legalForm: TaxpayerLegalForm.anonim),
        ),
      );

      expect(telemetry.keys, isEmpty);
      expect(repository.calls, contains('saveProfile'));
    });

    test('should not count a save that failed', () async {
      repository.nextFailure = const CacheFailure(message: 'disk');
      final SaveTaxProfileUseCase useCase = SaveTaxProfileUseCase(
        repository: repository,
        telemetry: telemetry,
      );

      final Either<Failure, void> result = await useCase(
        const SaveTaxProfileParams(
          profile: TaxpayerProfile.empty,
          fromWizard: true,
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(telemetry.keys, isEmpty);
    });
  });

  group('MarkTaxObligationUseCase', () {
    late MarkTaxObligationUseCase useCase;

    setUp(() {
      useCase = MarkTaxObligationUseCase(
        repository: repository,
        telemetry: telemetry,
      );
    });

    test('should route each mark to its own write', () async {
      await useCase(
        MarkTaxObligationParams(
          id: 1,
          mark: TaxObligationMark.declared,
          at: DateTime.utc(2026, 9),
        ),
      );
      await useCase(
        MarkTaxObligationParams(
          id: 1,
          mark: TaxObligationMark.paid,
          at: DateTime.utc(2026, 9),
        ),
      );

      expect(repository.calls, <String>['setDeclared', 'setPaid']);
    });

    test('should not record telemetry for filing or paying', () async {
      // Marking things done is ordinary use, not a signal about the catalog.
      await useCase(
        MarkTaxObligationParams(
          id: 1,
          mark: TaxObligationMark.paid,
          at: DateTime.utc(2026, 9),
        ),
      );

      expect(telemetry.keys, isEmpty);
    });

    test('should record a dismissal as the calendar being wrong', () async {
      await useCase(
        MarkTaxObligationParams(
          id: 1,
          mark: TaxObligationMark.dismissed,
          at: DateTime.utc(2026, 9),
        ),
      );

      expect(telemetry.keys, <String>['tax_item_removed']);
    });

    test('should not record undoing a dismissal', () async {
      // A user correcting a misclick is not evidence about the catalog.
      await useCase(
        const MarkTaxObligationParams(
          id: 1,
          mark: TaxObligationMark.dismissed,
          at: null,
        ),
      );

      expect(telemetry.keys, isEmpty);
    });
  });

  group('AnnotateTaxObligationUseCase', () {
    late AnnotateTaxObligationUseCase useCase;

    setUp(() {
      useCase = AnnotateTaxObligationUseCase(
        repository: repository,
        telemetry: telemetry,
      );
    });

    test('should touch only the fields the call names', () async {
      await useCase(
        const AnnotateTaxObligationParams(
          id: 1,
          note: 'not',
          editsNote: true,
        ),
      );

      expect(repository.calls, <String>['setNote:not']);
    });

    test('should let a note be cleared, not only replaced', () async {
      // "null means leave alone" would make clearing a note impossible.
      await useCase(
        const AnnotateTaxObligationParams(id: 1, editsNote: true),
      );

      expect(repository.calls, <String>['setNote:null']);
    });

    test('should record an edit as a signal', () async {
      await useCase(
        const AnnotateTaxObligationParams(
          id: 1,
          amountMinor: 1000,
          amountSource: TaxAmountSource.accountant,
          editsAmount: true,
        ),
      );

      expect(repository.calls, <String>['setAmount:accountant']);
      expect(telemetry.keys, <String>['tax_item_edited']);
    });

    test('should default an amount with no stated source to unknown',
        () async {
      await useCase(
        const AnnotateTaxObligationParams(
          id: 1,
          amountMinor: 1000,
          editsAmount: true,
        ),
      );

      expect(repository.calls, <String>['setAmount:unknown']);
    });

    test('should stop at the first failure', () async {
      repository.nextFailure = const CacheFailure(message: 'disk');

      final Either<Failure, void> result = await useCase(
        const AnnotateTaxObligationParams(
          id: 1,
          note: 'x',
          editsNote: true,
          amountMinor: 1,
          editsAmount: true,
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.calls, <String>['setNote:x']);
      expect(telemetry.keys, isEmpty);
    });
  });

  group('AddCustomTaxItemUseCase', () {
    late AddCustomTaxItemUseCase useCase;

    setUp(() {
      useCase = AddCustomTaxItemUseCase(
        repository: repository,
        telemetry: telemetry,
      );
    });

    test('should record what the catalog missed', () async {
      final Either<Failure, int> result = await useCase(
        AddCustomTaxItemParams(
          title: 'Kira stopajı',
          dueDate: DateTime.utc(2026, 10, 20),
        ),
      );

      expect(result.getOrElse(() => -1), 7);
      expect(telemetry.keys, <String>['tax_item_custom_added']);
    });

    test('should refuse a nameless item', () async {
      final Either<Failure, int> result = await useCase(
        AddCustomTaxItemParams(
          title: '   ',
          dueDate: DateTime.utc(2026, 10, 20),
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.calls, isEmpty);
      expect(telemetry.keys, isEmpty);
    });

    test('should trim the title before storing it', () async {
      await useCase(
        AddCustomTaxItemParams(
          title: '  Kira  ',
          dueDate: DateTime.utc(2026, 10, 20),
        ),
      );

      expect(repository.calls, <String>['addCustomItem:Kira']);
    });
  });
}
