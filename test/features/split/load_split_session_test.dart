import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/repositories/split_repository.dart';
import 'package:smartspend/features/split/domain/usecases/load_split_session.dart';

class _MockRepository extends Mock implements SplitRepository {}

void main() {
  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
  });

  group('LoadSplitSessionUseCase', () {
    final SplitSession session = SplitSession.bootstrap(
      receiptId: 3,
      storeName: 'BİM',
      receiptDate: DateTime.utc(2026, 3, 26),
      currency: 'TRY',
      totalMinor: 4000,
      items: const <SplitItem>[],
    );

    test('should hydrate the session for the receipt id', () async {
      when(() => repository.loadSession(3)).thenAnswer(
        (_) async => Right<Failure, SplitSession>(session),
      );

      final Either<Failure, SplitSession> result =
          await LoadSplitSessionUseCase(repository)(
            const LoadSplitSessionParams(receiptId: 3),
          );

      expect(result, Right<Failure, SplitSession>(session));
      verify(() => repository.loadSession(3)).called(1);
    });

    test('should surface CacheFailure for a locally deleted receipt', () async {
      when(() => repository.loadSession(3)).thenAnswer(
        (_) async => const Left<Failure, SplitSession>(
          CacheFailure(message: 'missing'),
        ),
      );

      final Either<Failure, SplitSession> result =
          await LoadSplitSessionUseCase(repository)(
            const LoadSplitSessionParams(receiptId: 3),
          );

      expect(result.isLeft(), isTrue);
    });

    test('should compare params by receipt id', () {
      expect(
        const LoadSplitSessionParams(receiptId: 3),
        const LoadSplitSessionParams(receiptId: 3),
      );
      expect(
        const LoadSplitSessionParams(receiptId: 3),
        isNot(const LoadSplitSessionParams(receiptId: 4)),
      );
    });
  });
}
