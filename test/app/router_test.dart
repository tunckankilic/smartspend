import 'package:flutter_test/flutter_test.dart';
import 'package:smartspend/app/router.dart';

void main() {
  group('resolveRedirect', () {
    group('onboarding incomplete', () {
      test('should pin an unauthenticated user to /onboarding', () {
        expect(
          resolveRedirect(
            onboardingDone: false,
            isAuthenticated: false,
            isUnauthenticated: true,
            location: '/',
          ),
          '/onboarding',
        );
      });

      test('should stay (null) when already at /onboarding', () {
        // Regression: this used to fall through to the auth rule and bounce
        // to /auth/sign-in, producing the loop
        // /onboarding -> /auth/sign-in -> /onboarding.
        expect(
          resolveRedirect(
            onboardingDone: false,
            isAuthenticated: false,
            isUnauthenticated: true,
            location: '/onboarding',
          ),
          isNull,
        );
      });

      test('should not bounce from /auth/sign-in back to /onboarding-loop', () {
        // The second leg of the old loop: at /auth/sign-in with onboarding
        // incomplete we send the user to onboarding exactly once, and once
        // there (previous case) they stay — no ping-pong.
        expect(
          resolveRedirect(
            onboardingDone: false,
            isAuthenticated: false,
            isUnauthenticated: true,
            location: '/auth/sign-in',
          ),
          '/onboarding',
        );
      });

      test('should pin even an authenticated user to /onboarding', () {
        expect(
          resolveRedirect(
            onboardingDone: false,
            isAuthenticated: true,
            isUnauthenticated: false,
            location: '/',
          ),
          '/onboarding',
        );
      });
    });

    group('onboarding complete', () {
      test('should redirect away from /onboarding to /', () {
        expect(
          resolveRedirect(
            onboardingDone: true,
            isAuthenticated: false,
            isUnauthenticated: true,
            location: '/onboarding',
          ),
          '/',
        );
      });

      test('should send unauthenticated users to /auth/sign-in', () {
        expect(
          resolveRedirect(
            onboardingDone: true,
            isAuthenticated: false,
            isUnauthenticated: true,
            location: '/',
          ),
          '/auth/sign-in',
        );
      });

      test('should let an unauthenticated user stay in the auth tree', () {
        expect(
          resolveRedirect(
            onboardingDone: true,
            isAuthenticated: false,
            isUnauthenticated: true,
            location: '/auth/sign-up',
          ),
          isNull,
        );
      });

      test('should send authenticated users out of the auth tree to /', () {
        expect(
          resolveRedirect(
            onboardingDone: true,
            isAuthenticated: true,
            isUnauthenticated: false,
            location: '/auth/sign-in',
          ),
          '/',
        );
      });

      test('should let an authenticated user stay on an app route', () {
        expect(
          resolveRedirect(
            onboardingDone: true,
            isAuthenticated: true,
            isUnauthenticated: false,
            location: '/dashboard',
          ),
          isNull,
        );
      });
    });

    group('pending auth state (initial/loading/failure)', () {
      test('should not redirect when neither authenticated nor '
          'unauthenticated', () {
        // App start: auth session not yet resolved. Navigation must stay put
        // rather than flashing the sign-in page before the session loads.
        expect(
          resolveRedirect(
            onboardingDone: true,
            isAuthenticated: false,
            isUnauthenticated: false,
            location: '/',
          ),
          isNull,
        );
      });
    });
  });
}
