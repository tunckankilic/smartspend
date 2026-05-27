// Cascades would tangle the await sequencing in these tests — opt out.
// ignore_for_file: cascade_invocations

import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categories/domain/entities/category.dart';
import 'package:smartspend/features/categorization/domain/engines/categorization_engine.dart';
import 'package:smartspend/features/categorization/domain/entities/categorization_suggestion.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_category_for_receipt.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_item.dart';
import 'package:smartspend/features/scan/domain/entities/scanned_receipt.dart';
import 'package:smartspend/features/scan/domain/repositories/scan_repository.dart';
import 'package:smartspend/features/scan/presentation/bloc/receipt_edit_bloc.dart';

class _MockRepo extends Mock implements ScanRepository {}

class _FakeFile extends Fake implements File {}

class _FakeReceipt extends Fake implements ScannedReceipt {}

/// Engine stub that always declines to categorize so tests exercise the
/// bloc's fallback path (pick "Market" if available, else first cat).
class _NoMatchEngine implements CategorizationEngine {
  const _NoMatchEngine();

  @override
  Future<void> warmUp() async {}

  @override
  Future<CategorizationSuggestion> suggest({
    required String? storeName,
    required List<String> itemNames,
    required List<Category> availableCategories,
  }) async {
    return const CategorizationSuggestion.none();
  }
}

/// Engine stub that returns a fixed suggestion regardless of input —
/// used to verify the bloc actually consults the engine.
class _FixedEngine implements CategorizationEngine {
  const _FixedEngine(this._suggestion);

  final CategorizationSuggestion _suggestion;

  @override
  Future<void> warmUp() async {}

  @override
  Future<CategorizationSuggestion> suggest({
    required String? storeName,
    required List<String> itemNames,
    required List<Category> availableCategories,
  }) async =>
      _suggestion;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeFile());
    registerFallbackValue(_FakeReceipt());
  });

  late _MockRepo repo;

  const Category market = Category(
    id: 1,
    name: 'Market',
    icon: 'shopping_cart',
    color: 0xFF4CAF50,
    isCustom: false,
  );
  const Category other = Category(
    id: 2,
    name: 'Diğer',
    icon: 'more_horiz',
    color: 0xFF9E9E9E,
    isCustom: false,
  );

  ScannedReceipt baseReceipt({
    List<ScannedItem>? items,
    DateTime? date,
    int total = 1150,
  }) {
    return ScannedReceipt(
      imagePath: '/tmp/x.jpg',
      storeName: 'BİM',
      date: date ?? DateTime.utc(2026, 4, 15),
      items: items ??
          const <ScannedItem>[
            ScannedItem(
              name: 'EKMEK',
              quantity: 1,
              unitPrice: 450,
              totalPrice: 450,
            ),
            ScannedItem(
              name: 'SÜT 1L',
              quantity: 2,
              unitPrice: 350,
              totalPrice: 700,
            ),
          ],
      total: total,
      currency: 'TRY',
      rawText: '',
      confidenceScore: 0.9,
    );
  }

  ReceiptEditBloc build({CategorizationEngine? engine}) => ReceiptEditBloc(
        repository: repo,
        suggestCategory: SuggestCategoryForReceiptUseCase(
          engine ?? const _NoMatchEngine(),
        ),
      );

  void mockCategoriesOK() {
    when(() => repo.listCategories()).thenAnswer(
      (_) async => const Right<Failure, List<Category>>(
        <Category>[market, other],
      ),
    );
  }

  setUp(() {
    repo = _MockRepo();
  });

  group('bootstrap', () {
    blocTest<ReceiptEditBloc, ReceiptEditState>(
      'ReceiptEditStarted should emit Ready with default category guessed',
      build: () {
        mockCategoriesOK();
        return build();
      },
      act: (ReceiptEditBloc b) =>
          b.add(ReceiptEditStarted(receipt: baseReceipt())),
      expect: () => <Matcher>[
        isA<ReceiptEditInitial>(),
        isA<ReceiptEditReady>(),
      ],
      verify: (ReceiptEditBloc b) {
        final ReceiptEditReady ready = b.state as ReceiptEditReady;
        expect(ready.defaultCategoryId, market.id);
        expect(ready.receipt.items.length, 2);
      },
    );

    blocTest<ReceiptEditBloc, ReceiptEditState>(
      'should seed an empty item when OCR produced none',
      build: () {
        mockCategoriesOK();
        return build();
      },
      act: (ReceiptEditBloc b) => b.add(
        ReceiptEditStarted(
          receipt: baseReceipt(items: const <ScannedItem>[]),
        ),
      ),
      verify: (ReceiptEditBloc b) {
        final ReceiptEditReady ready = b.state as ReceiptEditReady;
        expect(ready.receipt.items.length, 1);
      },
    );

    blocTest<ReceiptEditBloc, ReceiptEditState>(
      'should prefer engine suggestion over fallback market default',
      build: () {
        mockCategoriesOK();
        return build(
          engine: const _FixedEngine(
            CategorizationSuggestion(
              category: other,
              confidence: 0.95,
              source: CategorizationSource.keywordStore,
              matchedPattern: 'foo',
            ),
          ),
        );
      },
      act: (ReceiptEditBloc b) =>
          b.add(ReceiptEditStarted(receipt: baseReceipt())),
      verify: (ReceiptEditBloc b) {
        expect(
          (b.state as ReceiptEditReady).defaultCategoryId,
          other.id,
        );
      },
    );

    blocTest<ReceiptEditBloc, ReceiptEditState>(
      'should emit Failure when listCategories fails',
      build: () {
        when(() => repo.listCategories()).thenAnswer(
          (_) async => const Left<Failure, List<Category>>(
            CacheFailure(message: 'no db'),
          ),
        );
        return build();
      },
      act: (ReceiptEditBloc b) =>
          b.add(ReceiptEditStarted(receipt: baseReceipt())),
      expect: () => <Matcher>[
        isA<ReceiptEditInitial>(),
        isA<ReceiptEditFailure>(),
      ],
    );
  });

  group('field updates', () {
    Future<ReceiptEditBloc> primed() async {
      mockCategoriesOK();
      final ReceiptEditBloc b = build();
      b.add(ReceiptEditStarted(receipt: baseReceipt()));
      await Future<void>.delayed(Duration.zero);
      return b;
    }

    test('ReceiptStoreNameChanged updates the store', () async {
      final ReceiptEditBloc b = await primed();
      b.add(const ReceiptStoreNameChanged(storeName: 'A101'));
      await Future<void>.delayed(Duration.zero);
      expect(
        (b.state as ReceiptEditReady).receipt.storeName,
        'A101',
      );
    });

    test('ReceiptDateChanged updates the date', () async {
      final ReceiptEditBloc b = await primed();
      final DateTime newDate = DateTime.utc(2026, 5, 1);
      b.add(ReceiptDateChanged(date: newDate));
      await Future<void>.delayed(Duration.zero);
      expect((b.state as ReceiptEditReady).receipt.date, newDate);
    });

    test('ReceiptCurrencyChanged updates the currency', () async {
      final ReceiptEditBloc b = await primed();
      b.add(const ReceiptCurrencyChanged(currency: 'EUR'));
      await Future<void>.delayed(Duration.zero);
      expect((b.state as ReceiptEditReady).receipt.currency, 'EUR');
    });

    test('ReceiptDefaultCategoryChanged updates the default', () async {
      final ReceiptEditBloc b = await primed();
      b.add(ReceiptDefaultCategoryChanged(categoryId: other.id));
      await Future<void>.delayed(Duration.zero);
      expect(
        (b.state as ReceiptEditReady).defaultCategoryId,
        other.id,
      );
    });
  });

  group('item editing', () {
    test('ReceiptItemAdded should append an empty item', () async {
      mockCategoriesOK();
      final ReceiptEditBloc b = build();
      b.add(ReceiptEditStarted(receipt: baseReceipt()));
      await Future<void>.delayed(Duration.zero);

      b.add(const ReceiptItemAdded());
      await Future<void>.delayed(Duration.zero);

      expect((b.state as ReceiptEditReady).receipt.items.length, 3);
    });

    test('ReceiptItemRemoved should drop the indexed item', () async {
      mockCategoriesOK();
      final ReceiptEditBloc b = build();
      b.add(ReceiptEditStarted(receipt: baseReceipt()));
      await Future<void>.delayed(Duration.zero);

      b.add(const ReceiptItemRemoved(index: 0));
      await Future<void>.delayed(Duration.zero);

      final ReceiptEditReady ready = b.state as ReceiptEditReady;
      expect(ready.receipt.items.length, 1);
      expect(ready.receipt.items.first.name, 'SÜT 1L');
    });

    test('out-of-bounds remove is a no-op', () async {
      mockCategoriesOK();
      final ReceiptEditBloc b = build();
      b.add(ReceiptEditStarted(receipt: baseReceipt()));
      await Future<void>.delayed(Duration.zero);

      b.add(const ReceiptItemRemoved(index: 99));
      await Future<void>.delayed(Duration.zero);

      expect((b.state as ReceiptEditReady).receipt.items.length, 2);
    });

    test('ReceiptItemCategoryChanged sets the per-item category', () async {
      mockCategoriesOK();
      final ReceiptEditBloc b = build();
      b.add(ReceiptEditStarted(receipt: baseReceipt()));
      await Future<void>.delayed(Duration.zero);

      b.add(ReceiptItemCategoryChanged(index: 0, categoryId: other.id));
      await Future<void>.delayed(Duration.zero);

      final ScannedItem updated =
          (b.state as ReceiptEditReady).receipt.items[0];
      expect(updated.categoryId, other.id);
    });
  });

  group('validation + save', () {
    test('save with valid data emits Saving → Saved', () async {
      mockCategoriesOK();
      when(
        () => repo.saveReceipt(
          receipt: any(named: 'receipt'),
          defaultCategoryId: any(named: 'defaultCategoryId'),
        ),
      ).thenAnswer((_) async => const Right<Failure, int>(42));

      final ReceiptEditBloc b = build();
      final List<ReceiptEditState> states = <ReceiptEditState>[];
      final StreamSubscription<ReceiptEditState> sub =
          b.stream.listen(states.add);

      b.add(ReceiptEditStarted(receipt: baseReceipt()));
      await Future<void>.delayed(Duration.zero);
      b.add(const ReceiptEditSubmitted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(states.last, isA<ReceiptEditSaved>());
      expect((states.last as ReceiptEditSaved).receiptId, 42);

      await sub.cancel();
    });

    test('save with future date should surface futureDate error', () async {
      mockCategoriesOK();
      final ReceiptEditBloc b = build();
      b.add(
        ReceiptEditStarted(
          receipt: baseReceipt(
            date: DateTime.now().toUtc().add(const Duration(days: 5)),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      b.add(const ReceiptEditSubmitted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final ReceiptEditReady ready = b.state as ReceiptEditReady;
      expect(
        ready.validationErrors,
        contains(ReceiptEditValidationError.futureDate),
      );
      verifyNever(
        () => repo.saveReceipt(
          receipt: any(named: 'receipt'),
          defaultCategoryId: any(named: 'defaultCategoryId'),
        ),
      );
    });

    test('save without items should surface emptyItems error', () async {
      mockCategoriesOK();
      final ReceiptEditBloc b = build();
      b.add(ReceiptEditStarted(receipt: baseReceipt()));
      await Future<void>.delayed(Duration.zero);
      b
        ..add(const ReceiptItemRemoved(index: 0))
        ..add(const ReceiptItemRemoved(index: 0));
      await Future<void>.delayed(Duration.zero);

      b.add(const ReceiptEditSubmitted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final ReceiptEditReady ready = b.state as ReceiptEditReady;
      expect(
        ready.validationErrors,
        contains(ReceiptEditValidationError.emptyItems),
      );
    });

    test('computeTotal sums positive item totals only', () {
      const List<ScannedItem> items = <ScannedItem>[
        ScannedItem(
          name: 'A',
          quantity: 1,
          unitPrice: 100,
          totalPrice: 100,
        ),
        ScannedItem(
          name: '',
          quantity: 1,
          unitPrice: 200,
          totalPrice: 200,
        ),
        ScannedItem(
          name: 'C',
          quantity: 1,
          unitPrice: 0,
          totalPrice: 0,
        ),
      ];
      expect(ReceiptEditBloc.computeTotal(items), 300);
    });
  });
}
