import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/features/receipts/domain/entities/receipt_archive_entry.dart';
import 'package:smartspend/features/receipts/domain/entities/receipt_archive_filter.dart';
import 'package:smartspend/features/receipts/domain/repositories/receipt_archive_repository.dart';
import 'package:smartspend/features/receipts/domain/usecases/watch_receipt_archive.dart';

class _MockReceiptArchiveRepository extends Mock
    implements ReceiptArchiveRepository {}

void main() {
  late _MockReceiptArchiveRepository repository;
  late WatchReceiptArchiveUseCase useCase;

  setUpAll(() {
    registerFallbackValue(ReceiptArchiveFilter.empty);
  });

  setUp(() {
    repository = _MockReceiptArchiveRepository();
    useCase = WatchReceiptArchiveUseCase(repository);
  });

  group('WatchReceiptArchiveUseCase', () {
    final ReceiptArchiveEntry entry = ReceiptArchiveEntry(
      id: 1,
      date: DateTime.utc(2026, 5, 15),
      totalMinor: 5000,
      currency: 'TRY',
      storeName: 'Migros',
    );

    test('should delegate to repository.watchArchive with the given filter',
        () async {
      const ReceiptArchiveFilter filter = ReceiptArchiveFilter(
        searchQuery: 'Migros',
      );

      when(() => repository.watchArchive(any()))
          .thenAnswer((_) => Stream.value(<ReceiptArchiveEntry>[entry]));

      final Stream<List<ReceiptArchiveEntry>> result = useCase(filter);

      // Verify the correct filter was forwarded.
      verify(() => repository.watchArchive(filter)).called(1);
      final List<ReceiptArchiveEntry> emitted = await result.first;
      expect(emitted, <ReceiptArchiveEntry>[entry]);
    });

    test('should pass the empty filter through to the repository', () async {
      when(() => repository.watchArchive(any()))
          .thenAnswer((_) => Stream.value(<ReceiptArchiveEntry>[]));

      useCase(ReceiptArchiveFilter.empty);

      verify(() => repository.watchArchive(ReceiptArchiveFilter.empty))
          .called(1);
    });

    test('should return the same stream that the repository emits', () {
      final Stream<List<ReceiptArchiveEntry>> upstream =
          Stream.fromIterable(<List<ReceiptArchiveEntry>>[
        <ReceiptArchiveEntry>[entry],
        <ReceiptArchiveEntry>[],
      ]);

      when(() => repository.watchArchive(any())).thenAnswer((_) => upstream);

      final Stream<List<ReceiptArchiveEntry>> result =
          useCase(ReceiptArchiveFilter.empty);

      expect(result, same(upstream));
    });

    test('should propagate multiple emissions from the repository stream',
        () async {
      final List<ReceiptArchiveEntry> batch1 = <ReceiptArchiveEntry>[entry];
      final List<ReceiptArchiveEntry> batch2 = <ReceiptArchiveEntry>[];

      when(() => repository.watchArchive(any()))
          .thenAnswer((_) => Stream.fromIterable(
                <List<ReceiptArchiveEntry>>[batch1, batch2],
              ));

      final List<List<ReceiptArchiveEntry>> emitted =
          await useCase(ReceiptArchiveFilter.empty).toList();

      expect(emitted, <List<ReceiptArchiveEntry>>[batch1, batch2]);
    });
  });
}
