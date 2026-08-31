# Contributing to SmartSpend

Thanks for your interest! SmartSpend is a portfolio project, but it's built to
production standards — these conventions keep it that way.

## Ground rules

- **Architecture:** Clean Architecture, dependencies inward only
  (`presentation → domain ← data`). The presentation layer never imports
  `data`. Every fallible repository/use-case returns `Either<Failure, T>`.
- **State:** BLoC + Cubit only — no Riverpod, GetX, Provider, or `setState`.
  Business logic lives in use cases, never in widgets. Repositories are called
  through use cases, never directly from a BLoC or widget.
- **Money** is `int` (minor units / kuruş) — never `double`. Timestamps are
  **UTC** in storage, localized only for display.
- **No** `print` (use `Logger`), **no** `dynamic`, **no** `!` null assertion.
  Prefer `final` over `var`. 80-character line limit. `const` constructors.
  `Equatable` on every entity / event / state. Package imports only
  (no relative imports).
- **User-facing strings** are always localized via `AppLocalizations` in all
  three locales (TR / EN / DE) — never hardcode UI text.
- **Security:** the Gemini key and Supabase `service_role` key never enter the
  Flutter app. Only the anon key + public client IDs ship, via
  `--dart-define-from-file=.env`. RLS stays enabled on every table. Never log
  tokens, JWTs, or secrets.

The full rule set lives in [`CLAUDE.md`](CLAUDE.md).

## Branch naming

```
feature/{feature-name}
fix/{bug-name}
refactor/{scope}
chore/{scope}
```

One feature per branch, one PR per feature. PRs are squash-merged to `main`.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org):

```
feat(scan): add OCR receipt scanning with ML Kit
fix(expense): correct currency conversion rounding
test(budget): add BudgetBloc unit tests
refactor(core): extract common widgets to shared
chore(supabase): add receipts table migration
docs(readme): add architecture diagram
```

## Toolchain

The Flutter version is pinned in **`.fvmrc`** and that pin is the only one —
`codemagic.yaml` must request the same version, and
`test/repo/toolchain_pin_test.dart` fails the suite if they ever drift apart or
if you are running a different Dart SDK locally.

```bash
fvm use                         # if you use fvm: installs and selects the pin
flutter --version               # otherwise: confirm it matches .fvmrc
```

Bumping Flutter is a three-file change: `.fvmrc`, the `expectedDartSdk`
constant in `test/repo/toolchain_pin_test.dart`, and both `flutter:` keys in
`codemagic.yaml`.

## Setup & codegen

Generated files (`*.g.dart`, `lib/l10n/generated/`) are **not committed** — run
codegen after a fresh checkout and after any schema/DI/ARB change:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift + DI
flutter gen-l10n                                            # localizations
```

## Running tests

```bash
flutter test                    # full Flutter suite
flutter test --coverage         # with coverage

# Integration tests run on a device/simulator:
flutter test integration_test/offline_sync_flow_test.dart -d <device>

# Backend tests (need a local Supabase stack: `supabase start`):
supabase db lint
supabase test db                # pgTAP RLS suite
deno test --allow-env supabase/functions/__tests__/   # Edge Function tests
```

Use `mocktail` for mocking (not `mockito`) and `bloc_test` for BLoCs. Test
descriptions are in English and start with "should …". Target ≥ 80% line
coverage (current baseline: 79.3%, generated sources excluded).

## Feature flags

Work that is not shipping in the current release lives behind a
`FeatureFlag`, and **every flag has a death date**. `shipsIn`, `removeBy` and
`owner` are required constructor arguments, so a flag cannot be added without
one, and `test/core/services/feature_flag_lifecycle_test.dart` fails the build
when a flag outlives its `removeBy` — or when a flag whose release already
shipped is still referenced nowhere in `lib/`.

When that gate fires, the fix is to delete the flag and inline the branch it
guarded. Pushing `removeBy` out is a decision worth making on purpose, in its
own commit, with a reason.

## Releasing

`pubspec.yaml` is the **only** place the version is written. iOS reads it
through `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`, Android through
`flutter.versionName` / `flutter.versionCode`, and
`test/repo/version_pin_test.dart` fails the suite if either platform starts
keeping its own copy.

One tag per release, in `vX.Y.Z` form:

```bash
git tag v1.3.0 <commit-that-shipped>     # annotated is fine too
git push origin v1.3.0
```

The tag has to point at a commit whose `pubspec.yaml` says the same version —
the `release` workflow refuses to build when they disagree, rather than
shipping a build labelled with a version the source tree never carried.

Order of operations:

1. Bump `pubspec.yaml` in a PR and merge it.
2. Merging to `main` builds a signed IPA and uploads it to TestFlight
   automatically. App Store submission stays manual.
3. Once the release is submitted, tag that commit and push the tag.

Two things to know: pushing the tag triggers one **extra** TestFlight build
(with a fresh build number — harmless, App Store Connect only rejects
duplicates), and a published tag is never moved or deleted, since it is the
record of what shipped. Releases before 1.2.1 predate this rule and carry no
tags.

## PR checklist

Before opening a PR, confirm:

- [ ] `flutter analyze --fatal-infos` reports **0 issues**
- [ ] `flutter test` is **all green**
- [ ] New/changed behavior has tests (unit + BLoC/widget as appropriate)
- [ ] User-facing strings added to **all three** ARB files (TR / EN / DE)
- [ ] No `print` / `dynamic` / `!` / relative imports introduced
- [ ] Money handled as `int`; timestamps stored UTC
- [ ] If a table changed: RLS policy added + pgTAP test, `supabase db lint`
      clean
- [ ] No secrets, keys, or tokens committed or logged
- [ ] Generated files **not** committed
- [ ] Commit messages follow Conventional Commits
