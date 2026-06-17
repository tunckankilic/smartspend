import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartspend/core/services/onboarding_flag_store.dart';

void main() {
  group('OnboardingFlagStore', () {
    late SharedPreferences prefs;
    late OnboardingFlagStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      store = OnboardingFlagStore(prefs);
    });

    test('should return false when the flag has never been set', () {
      expect(store.isComplete, isFalse);
    });

    test('should return true after markComplete() is called', () async {
      await store.markComplete();
      expect(store.isComplete, isTrue);
    });

    test('should return false after reset() is called following markComplete()',
        () async {
      await store.markComplete();
      await store.reset();
      expect(store.isComplete, isFalse);
    });

    test('should read the initial value when prefs already contain the key',
        () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'onboarding.complete': true},
      );
      prefs = await SharedPreferences.getInstance();
      final OnboardingFlagStore prefilled = OnboardingFlagStore(prefs);

      expect(prefilled.isComplete, isTrue);
    });

    test('should persist the value across re-reads of the same prefs instance',
        () async {
      await store.markComplete();
      // Re-read from the same instance (SharedPreferences is a singleton).
      final bool result = prefs.getBool('onboarding.complete') ?? false;
      expect(result, isTrue);
    });

    test('should remove the key from prefs on reset()', () async {
      await store.markComplete();
      await store.reset();
      expect(prefs.containsKey('onboarding.complete'), isFalse);
    });
  });
}
