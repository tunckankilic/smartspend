import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/split/domain/entities/split_item.dart';
import 'package:smartspend/features/split/domain/entities/split_session.dart';
import 'package:smartspend/features/split/domain/entities/split_type.dart';
import 'package:smartspend/features/split/domain/usecases/load_split_session.dart';
import 'package:smartspend/features/split/presentation/bloc/split_bloc.dart';

class _MockLoad extends Mock implements LoadSplitSessionUseCase {}

class _FakeShareSink implements SplitShareSink {
  _FakeShareSink();

  bool shouldThrow = false;
  final List<String> shared = <String>[];

  @override
  Future<void> share(String text) async {
    if (shouldThrow) {
      throw StateError('share dismissed');
    }
    shared.add(text);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const LoadSplitSessionParams(receiptId: 0));
  });

  late _MockLoad load;
  late _FakeShareSink sink;

  SplitSession baseSession() => SplitSession.bootstrap(
        receiptId: 7,
        storeName: 'Migros',
        receiptDate: DateTime.utc(2026, 5, 28),
        currency: 'TRY',
        totalMinor: 30000,
        items: const <SplitItem>[
          SplitItem(id: 1, name: 'Süt', totalPriceMinor: 10000),
          SplitItem(id: 2, name: 'Ekmek', totalPriceMinor: 20000),
        ],
      );

  setUp(() {
    load = _MockLoad();
    sink = _FakeShareSink();
  });

  SplitBloc buildBloc() => SplitBloc(loadSession: load, shareSink: sink);

  group('SplitBloc - load', () {
    blocTest<SplitBloc, SplitState>(
      'should emit [Loading, Loaded] on successful load',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) => b.add(const SplitStarted(receiptId: 7)),
      expect: () => <Matcher>[
        isA<SplitLoading>(),
        isA<SplitLoaded>().having(
          (SplitLoaded s) => s.session.totalMinor,
          'totalMinor',
          30000,
        ),
      ],
    );

    blocTest<SplitBloc, SplitState>(
      'should emit [Loading, Error] when repository fails',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => const Left<Failure, SplitSession>(
            CacheFailure(message: 'gone'),
          ),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) => b.add(const SplitStarted(receiptId: 7)),
      expect: () => <Matcher>[
        isA<SplitLoading>(),
        isA<SplitError>(),
      ],
    );
  });

  group('SplitBloc - participants', () {
    blocTest<SplitBloc, SplitState>(
      'should add participant and recompute totals',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b.add(const SplitParticipantAdded(name: 'Ali'));
      },
      skip: 2, // Loading + initial Loaded with 0 participants.
      expect: () => <Matcher>[
        isA<SplitLoaded>()
            .having(
              (SplitLoaded s) => s.session.participants.length,
              'participants.length',
              1,
            )
            .having(
              (SplitLoaded s) => s.perPersonMinor['p1'],
              'p1 share',
              30000,
            ),
      ],
    );

    blocTest<SplitBloc, SplitState>(
      'should reject blank participant names',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b.add(const SplitParticipantAdded(name: '   '));
      },
      skip: 2,
      expect: () => <Matcher>[],
    );

    blocTest<SplitBloc, SplitState>(
      'should remove participant and scrub their assignments',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b
          ..add(const SplitParticipantAdded(name: 'Ali'))
          ..add(const SplitParticipantAdded(name: 'Mehmet'))
          ..add(const SplitTypeChanged(type: SplitType.custom))
          ..add(
            const SplitItemAssigned(itemId: 1, participantIds: <String>['p1']),
          )
          ..add(const SplitParticipantRemoved(participantId: 'p1'));
      },
      verify: (SplitBloc b) {
        final SplitLoaded s = b.state as SplitLoaded;
        expect(s.session.participants.length, 1);
        expect(s.session.participants.single.id, 'p2');
        expect(s.session.assignments, isEmpty);
      },
    );
  });

  group('SplitBloc - assignments', () {
    blocTest<SplitBloc, SplitState>(
      'should clear an item when assignment list is empty',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b
          ..add(const SplitParticipantAdded(name: 'Ali'))
          ..add(const SplitTypeChanged(type: SplitType.custom))
          ..add(
            const SplitItemAssigned(itemId: 1, participantIds: <String>['p1']),
          )
          ..add(
            const SplitItemAssigned(itemId: 1, participantIds: <String>[]),
          );
      },
      verify: (SplitBloc b) {
        final SplitLoaded s = b.state as SplitLoaded;
        expect(s.session.assignments.containsKey(1), isFalse);
      },
    );

    blocTest<SplitBloc, SplitState>(
      'should switch between equal and custom totals',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b
          ..add(const SplitParticipantAdded(name: 'Ali'))
          ..add(const SplitParticipantAdded(name: 'Mehmet'))
          ..add(
            const SplitItemAssigned(itemId: 1, participantIds: <String>['p1']),
          )
          ..add(
            const SplitItemAssigned(itemId: 2, participantIds: <String>['p2']),
          )
          // Initially equal → both 15000 regardless of assignments.
          ..add(const SplitTypeChanged(type: SplitType.custom));
      },
      verify: (SplitBloc b) {
        final SplitLoaded s = b.state as SplitLoaded;
        expect(s.session.splitType, SplitType.custom);
        expect(s.perPersonMinor['p1'], 10000);
        expect(s.perPersonMinor['p2'], 20000);
      },
    );
  });

  group('SplitBloc - share', () {
    blocTest<SplitBloc, SplitState>(
      'should forward payload to the share sink',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b
          ..add(const SplitParticipantAdded(name: 'Ali'))
          ..add(const SplitShareRequested(payload: 'hello'));
      },
      verify: (SplitBloc b) {
        expect(sink.shared, <String>['hello']);
      },
    );

    blocTest<SplitBloc, SplitState>(
      'should skip share when there are no participants',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b.add(const SplitShareRequested(payload: 'hello'));
      },
      verify: (SplitBloc b) {
        expect(sink.shared, isEmpty);
      },
    );

    blocTest<SplitBloc, SplitState>(
      'should surface transientFailure when sink throws',
      setUp: () {
        when(() => load(any())).thenAnswer(
          (_) async => Right<Failure, SplitSession>(baseSession()),
        );
        sink.shouldThrow = true;
      },
      build: buildBloc,
      act: (SplitBloc b) async {
        b.add(const SplitStarted(receiptId: 7));
        await Future<void>.delayed(Duration.zero);
        b
          ..add(const SplitParticipantAdded(name: 'Ali'))
          ..add(const SplitShareRequested(payload: 'hello'));
      },
      verify: (SplitBloc b) {
        final SplitLoaded s = b.state as SplitLoaded;
        expect(s.transientFailure, isNotNull);
      },
    );
  });
}
