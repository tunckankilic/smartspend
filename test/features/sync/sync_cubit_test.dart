import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/core/services/sync_service.dart';
import 'package:smartspend/features/sync/presentation/bloc/sync_cubit.dart';

class _MockSyncService extends Mock implements SyncService {}

class _MockConnectivity extends Mock implements Connectivity {}

void main() {
  late _MockSyncService service;
  late _MockConnectivity connectivity;

  setUp(() {
    service = _MockSyncService();
    connectivity = _MockConnectivity();
    // Defaults: empty streams + a no-op sync.
    when(() => service.watchStatus())
        .thenAnswer((_) => const Stream<SyncPhase>.empty());
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => const Stream<List<ConnectivityResult>>.empty());
    when(() => service.sync()).thenAnswer(
      (_) async => const Right<Failure, SyncReport>(SyncReport()),
    );
  });

  SyncCubit build() =>
      SyncCubit(service: service, connectivity: connectivity);

  group('phase mapping', () {
    final DateTime at = DateTime.utc(2026, 5, 29, 10);

    blocTest<SyncCubit, SyncState>(
      'should map each SyncPhase to its SyncState on start',
      build: () {
        when(() => service.watchStatus()).thenAnswer(
          (_) => Stream<SyncPhase>.fromIterable(<SyncPhase>[
            const SyncPhaseSyncing(),
            const SyncPhasePending(count: 3),
            SyncPhaseSynced(lastSyncAt: at),
          ]),
        );
        return build();
      },
      act: (SyncCubit cubit) => cubit.start(),
      expect: () => <SyncState>[
        const SyncInProgress(),
        const SyncPending(count: 3),
        SyncSynced(lastSyncAt: at),
      ],
    );

    blocTest<SyncCubit, SyncState>(
      'should emit SyncOffline when the engine reports offline',
      build: () {
        when(() => service.watchStatus()).thenAnswer(
          (_) => Stream<SyncPhase>.value(const SyncPhaseOffline()),
        );
        return build();
      },
      act: (SyncCubit cubit) => cubit.start(),
      expect: () => <SyncState>[const SyncOffline()],
    );
  });

  group('syncNow', () {
    blocTest<SyncCubit, SyncState>(
      'should emit SyncConflict when the run resolves conflicts',
      build: () {
        when(() => service.sync()).thenAnswer(
          (_) async =>
              const Right<Failure, SyncReport>(SyncReport(conflicts: 2)),
        );
        return build();
      },
      act: (SyncCubit cubit) => cubit.syncNow(),
      expect: () => <SyncState>[const SyncConflict(count: 2)],
    );

    blocTest<SyncCubit, SyncState>(
      'should emit SyncFailed when the run fails outright',
      build: () {
        when(() => service.sync()).thenAnswer(
          (_) async => const Left<Failure, SyncReport>(
            SyncFailure(message: 'boom'),
          ),
        );
        return build();
      },
      act: (SyncCubit cubit) => cubit.syncNow(),
      expect: () => <SyncState>[
        const SyncFailed(failure: SyncFailure(message: 'boom')),
      ],
    );

    blocTest<SyncCubit, SyncState>(
      'should emit nothing when a clean run reports no conflicts',
      build: build,
      act: (SyncCubit cubit) => cubit.syncNow(),
      expect: () => <SyncState>[],
    );
  });

  group('connectivity', () {
    blocTest<SyncCubit, SyncState>(
      'should trigger a sync when connectivity is restored',
      build: () {
        when(() => connectivity.onConnectivityChanged).thenAnswer(
          (_) => Stream<List<ConnectivityResult>>.value(
            <ConnectivityResult>[ConnectivityResult.wifi],
          ),
        );
        return build();
      },
      act: (SyncCubit cubit) => cubit.start(),
      verify: (_) => verify(() => service.sync()).called(1),
    );

    blocTest<SyncCubit, SyncState>(
      'should not sync while the device stays offline',
      build: () {
        when(() => connectivity.onConnectivityChanged).thenAnswer(
          (_) => Stream<List<ConnectivityResult>>.value(
            <ConnectivityResult>[ConnectivityResult.none],
          ),
        );
        return build();
      },
      act: (SyncCubit cubit) => cubit.start(),
      verify: (_) => verifyNever(() => service.sync()),
    );
  });
}
