import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categorization/domain/entities/user_correction.dart';
import 'package:smartspend/features/categorization/domain/repositories/user_correction_repository.dart';
import 'package:smartspend/features/categorization/domain/usecases/record_user_correction.dart';

class _MockRepo extends Mock implements UserCorrectionRepository {}

class _SilentLogger extends Logger {
  _SilentLogger() : super(level: Level.off);
}

void main() {
  late _MockRepo repo;
  late RecordUserCorrectionUseCase usecase;

  final UserCorrection correction = UserCorrection(
    storeName: 'BİM',
    oldCategoryId: 3,
    newCategoryId: 5,
    occurredAt: DateTime.utc(2026, 5, 1),
  );

  setUpAll(() {
    registerFallbackValue(correction);
  });

  setUp(() {
    repo = _MockRepo();
    usecase = RecordUserCorrectionUseCase(
      repository: repo,
      logger: _SilentLogger(),
    );
  });

  test('should forward the correction to the repository on success', () async {
    when(() => repo.record(any()))
        .thenAnswer((_) async => const Right<Failure, Unit>(unit));

    final Either<Failure, void> result = await usecase(
      RecordUserCorrectionParams(correction: correction),
    );

    expect(result.isRight(), isTrue);
    verify(() => repo.record(correction)).called(1);
  });

  test('should propagate a repository failure as Left', () async {
    when(() => repo.record(any())).thenAnswer(
      (_) async => const Left<Failure, Unit>(
        CacheFailure(message: 'disk full'),
      ),
    );

    final Either<Failure, void> result = await usecase(
      RecordUserCorrectionParams(correction: correction),
    );

    expect(result.isLeft(), isTrue);
    expect(
      result.swap().getOrElse(() => throw StateError('right')),
      isA<CacheFailure>(),
    );
  });

  test('params should be value-equal for the same correction', () {
    expect(
      RecordUserCorrectionParams(correction: correction),
      RecordUserCorrectionParams(correction: correction),
    );
  });
}
