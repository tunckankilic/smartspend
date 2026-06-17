import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/features/split/domain/entities/split_type.dart';

void main() {
  group('SplitType', () {
    group('values', () {
      test('should expose exactly two members', () {
        expect(SplitType.values, hasLength(2));
      });

      test('should contain equal and custom', () {
        expect(SplitType.values, containsAll(<SplitType>[
          SplitType.equal,
          SplitType.custom,
        ]));
      });
    });

    group('names', () {
      test('should have name "equal" for SplitType.equal', () {
        expect(SplitType.equal.name, 'equal');
      });

      test('should have name "custom" for SplitType.custom', () {
        expect(SplitType.custom.name, 'custom');
      });
    });

    group('fromName', () {
      test('should return SplitType.equal for the string "equal"', () {
        expect(SplitType.fromName('equal'), SplitType.equal);
      });

      test('should return SplitType.custom for the string "custom"', () {
        expect(SplitType.fromName('custom'), SplitType.custom);
      });

      test('should return null for an unknown name', () {
        expect(SplitType.fromName('unknown'), isNull);
      });

      test('should return null for an empty string', () {
        expect(SplitType.fromName(''), isNull);
      });

      test('should return null for a name with different casing', () {
        expect(SplitType.fromName('Equal'), isNull);
        expect(SplitType.fromName('CUSTOM'), isNull);
      });

      test('should round-trip for every member via its own name', () {
        for (final SplitType v in SplitType.values) {
          expect(SplitType.fromName(v.name), v);
        }
      });
    });
  });
}
