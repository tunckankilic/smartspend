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
