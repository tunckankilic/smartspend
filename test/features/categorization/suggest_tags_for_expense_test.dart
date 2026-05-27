import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/error/failures.dart';
import 'package:smartspend/features/categorization/domain/usecases/suggest_tags_for_expense.dart';

void main() {
  const SuggestTagsForExpenseUseCase useCase = SuggestTagsForExpenseUseCase();

  Future<List<String>> run(String text, List<String> existing) async {
    final Either<Failure, List<String>> r = await useCase(
      SuggestTagsParams(text: text, existingTags: existing),
    );
    return r.getOrElse(() => const <String>[]);
  }

  test('"kahve molası" yields a kahve tag', () async {
    expect(await run('öğle kahve molası', const <String>[]), contains('kahve'));
  });

  test('"business lunch" yields a iş tag (EN trigger)', () async {
    expect(await run('quick business lunch', const <String>[]),
        contains('iş'));
  });

  test('matches multiple non-overlapping triggers in one input', () async {
    final List<String> tags = await run(
      'iş yemeği sonrası taksi',
      const <String>[],
    );
    expect(tags, containsAll(<String>['iş', 'ulaşım']));
  });

  test('case-insensitive against existingTags suppresses duplicates',
      () async {
    final List<String> tags =
        await run('kahve molası', const <String>['Kahve']);
    expect(tags, isEmpty);
  });

  test('empty input yields no suggestions', () async {
    expect(await run('   ', const <String>[]), isEmpty);
  });

  test('text with no triggers yields no suggestions', () async {
    expect(
      await run('miscellaneous purchase without triggers', const <String>[]),
      isEmpty,
    );
  });

  test('returns each tag at most once even with multiple keyword hits',
      () async {
    final List<String> tags =
        await run('kahve cappuccino latte', const <String>[]);
    expect(tags, <String>['kahve']);
  });
}
