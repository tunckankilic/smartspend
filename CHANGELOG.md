# Changelog

All notable changes to SmartSpend are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **PDF export** — monthly spending report generated server-side by the
  `export-pdf` Edge Function, downloadable from Settings alongside CSV export.
- **CI/CD** — Codemagic pipeline (`codemagic.yaml`) with `pr-check`, `release`
  (TestFlight), and `supabase-deploy` workflows.
- **Docs** — Mermaid architecture diagrams in the README, `CONTRIBUTING.md`,
  screenshot placeholders, and the App Store submission kit under
  `docs/internal/appstore/` (localized descriptions + GDPR/KVKK privacy policy).

### Changed
- Migrated `share_plus` usage to the `SharePlus.instance.share(ShareParams)`
  API (the static `Share.share` was deprecated in share_plus 13).

## [1.0.0] — TBD

First App Store release. Built over 10 weekly sprints.

### Added
- Receipt scanning with on-device OCR (Google ML Kit) + Gemini Vision fallback.
- Self-learning hybrid expense categorization (corrections → keywords → TFLite).
- Dashboard with charts, period comparisons, and generated insights.
- Budgets with per-category caps, threshold alerts, and progress rings.
- Receipt archive with warranty-expiry reminders.
- Bill splitting with shareable results.
- Settings: currency, locale (TR/EN/DE), dark mode, notifications, CSV export.
- Supabase backend: Auth (email/Google/Apple), Postgres + RLS, Storage, Edge
  Functions, Realtime.
- Offline-first architecture with background sync (last-write-wins) and a
  per-row-isolated sync queue.
- Observability with Sentry (crash, performance, breadcrumbs) and a secret
  scrubber.
- 600+ tests (unit, BLoC, repository, widget, integration), pgTAP RLS suite,
  and Deno Edge Function tests.
