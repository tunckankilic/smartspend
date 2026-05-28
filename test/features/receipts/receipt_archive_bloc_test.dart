import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/domain/usecases/watch_receipt_archive.dart';
import 'package:smartspend/features/receipts/presentation/bloc/receipt_archive_bloc.dart';

class _MockWatch extends Mock implements WatchReceiptArchiveUseCase {}

ReceiptArchiveEntry _entry(int id, {String? store, DateTime? date}) {
  return ReceiptArchiveEntry(
    id: id,
    storeName: store ?? 'Store $id',
    date: date ?? DateTime.utc(2026, 5, id),
    totalMinor: id * 1000,
    currency: 'TRY',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(ReceiptArchiveFilter.empty);
  });

  late _MockWatch watch;
  late StreamController<List<ReceiptArchiveEntry>> controller;

  setUp(() {
    watch = _MockWatch();
    controller = StreamController<List<ReceiptArchiveEntry>>.broadcast();
    when(() => watch(any())).thenAnswer((_) => controller.stream);
  });

  tearDown(() => controller.close());

  ReceiptArchiveBloc buildBloc() =>
      ReceiptArchiveBloc(watchArchive: watch);

  group('ReceiptArchiveBloc - subscribe', () {
    blocTest<ReceiptArchiveBloc, ReceiptArchiveState>(
      'should emit Loading then Loaded when the stream ticks',
      build: buildBloc,
      act: (ReceiptArchiveBloc b) async {
        b.add(const ReceiptArchiveSubscribed());
        await Future<void>.delayed(Duration.zero);
        controller.add(<ReceiptArchiveEntry>[_entry(1), _entry(2)]);
      },
      wait: const Duration(milliseconds: 10),
      expect: () => <Matcher>[
        isA<ReceiptArchiveLoading>(),
        isA<ReceiptArchiveLoaded>().having(
          (ReceiptArchiveLoaded s) => s.entries.length,
          'entries.length',
          2,
        ),
      ],
    );
  });

  group('ReceiptArchiveBloc - filters', () {
    blocTest<ReceiptArchiveBloc, ReceiptArchiveState>(
      'should re-subscribe with updated filter when search changes',
      build: buildBloc,
      act: (ReceiptArchiveBloc b) async {
        b.add(const ReceiptArchiveSubscribed());
        await Future<void>.delayed(Duration.zero);
        controller.add(<ReceiptArchiveEntry>[_entry(1)]);
        await Future<void>.delayed(Duration.zero);
        b.add(const ReceiptArchiveSearchChanged(query: 'migros'));
        // Wait past the 300ms debounce.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      wait: const Duration(milliseconds: 400),
      verify: (_) {
        // First call: empty filter. Second call: search='migros'.
        final List<ReceiptArchiveFilter> filters = verify(
          () => watch(captureAny()),
        ).captured.cast<ReceiptArchiveFilter>();
        expect(filters.length, greaterThanOrEqualTo(2));
        expect(filters.last.searchQuery, 'migros');
      },
    );

    blocTest<ReceiptArchiveBloc, ReceiptArchiveState>(
      'should clear search when query is blank',
      build: buildBloc,
      act: (ReceiptArchiveBloc b) async {
        b.add(const ReceiptArchiveSubscribed());
        await Future<void>.delayed(Duration.zero);
        controller.add(<ReceiptArchiveEntry>[]);
        b.add(const ReceiptArchiveSearchChanged(query: '   '));
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      wait: const Duration(milliseconds: 400),
      verify: (_) {
        final List<ReceiptArchiveFilter> filters = verify(
          () => watch(captureAny()),
        ).captured.cast<ReceiptArchiveFilter>();
        expect(filters.last.searchQuery, isNull);
      },
    );

    blocTest<ReceiptArchiveBloc, ReceiptArchiveState>(
      'should re-subscribe when date range changes',
      build: buildBloc,
      act: (ReceiptArchiveBloc b) async {
        b.add(const ReceiptArchiveSubscribed());
        await Future<void>.delayed(Duration.zero);
        controller.add(<ReceiptArchiveEntry>[]);
        b.add(
          ReceiptArchiveDateRangeChanged(
            from: DateTime.utc(2026, 5, 1),
            to: DateTime.utc(2026, 5, 31),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      wait: const Duration(milliseconds: 100),
      verify: (_) {
        final List<ReceiptArchiveFilter> filters = verify(
          () => watch(captureAny()),
        ).captured.cast<ReceiptArchiveFilter>();
        expect(filters.last.from, isNotNull);
        expect(filters.last.to, isNotNull);
      },
    );
  });

  group('ReceiptArchiveBloc - view toggle', () {
    blocTest<ReceiptArchiveBloc, ReceiptArchiveState>(
      'should flip between grid and list layout',
      build: buildBloc,
      act: (ReceiptArchiveBloc b) async {
        b.add(const ReceiptArchiveSubscribed());
        await Future<void>.delayed(Duration.zero);
        controller.add(<ReceiptArchiveEntry>[_entry(1)]);
        await Future<void>.delayed(Duration.zero);
        b.add(const ReceiptArchiveViewToggled());
      },
      wait: const Duration(milliseconds: 50),
      verify: (ReceiptArchiveBloc b) {
        final ReceiptArchiveLoaded s = b.state as ReceiptArchiveLoaded;
        expect(s.layout, ReceiptArchiveLayout.list);
      },
    );

    blocTest<ReceiptArchiveBloc, ReceiptArchiveState>(
      'should default to grid layout on first load',
      build: buildBloc,
      act: (ReceiptArchiveBloc b) async {
        b.add(const ReceiptArchiveSubscribed());
        await Future<void>.delayed(Duration.zero);
        controller.add(<ReceiptArchiveEntry>[_entry(1)]);
      },
      wait: const Duration(milliseconds: 30),
      verify: (ReceiptArchiveBloc b) {
        final ReceiptArchiveLoaded s = b.state as ReceiptArchiveLoaded;
        expect(s.layout, ReceiptArchiveLayout.grid);
      },
    );
  });

  group('ReceiptArchiveBloc - error', () {
    blocTest<ReceiptArchiveBloc, ReceiptArchiveState>(
      'should emit Error when the stream errors',
      build: buildBloc,
      act: (ReceiptArchiveBloc b) async {
        b.add(const ReceiptArchiveSubscribed());
        await Future<void>.delayed(Duration.zero);
        controller.addError(StateError('boom'));
      },
      wait: const Duration(milliseconds: 30),
      expect: () => <Matcher>[
        isA<ReceiptArchiveLoading>(),
        isA<ReceiptArchiveError>(),
      ],
    );
  });
}
