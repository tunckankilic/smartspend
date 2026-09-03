# Changelog

All notable changes to SmartSpend are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **PDF export** — monthly spending report generated server-side by the
  `export-pdf` Edge Function, downloadable from Settings alongside CSV export.
  Renders Turkish (ı/İ/ş/ğ) and German exactly via an embedded Roboto Unicode
  font, with a graceful Helvetica fallback if the font can't be fetched.
- **CI/CD** — Codemagic pipeline (`codemagic.yaml`) with `pr-check`, `release`
  (TestFlight), and `supabase-deploy` workflows.
- **Docs** — Mermaid architecture diagrams in the README, `CONTRIBUTING.md`,
  screenshot placeholders, and the App Store submission kit under
  `docs/internal/appstore/` (localized descriptions + GDPR/KVKK privacy policy).

### Changed
- Migrated `share_plus` usage to the `SharePlus.instance.share(ShareParams)`
  API (the static `Share.share` was deprecated in share_plus 13).

## [1.3.0] — 2026-09-04

Zemin sürümü. Kullanıcıya görünen tek yeni özellik vergi/ödeme takvimi;
altında duran işin çoğu, sonraki sürümlerin üstüne kurulacağı temel.

### Added
- **Vergi ve ödeme takvimi.** Mükellefiyet profilinden (sekiz soru) beyanname
  ve ödeme son günleri üretiliyor, hafta sonu/tatil ötelemesiyle. Kalıcı
  ücretsiz.
  🚨 **Hiçbir tutar hesaplanmıyor.** Tutar yalnız birinin yazdığı yerde
  görünür; "uygulama hesapladı" anlamına gelen bir alan veri modelinde yok ve
  bunu bir test zorluyor. Beyanname verilmiyor, GİB'e hiçbir şey iletilmiyor.
- **Son gün hatırlatmaları**, üç dilde. Her bildirim tarihin nereden geldiğini
  söylüyor ve muhasebeciye teyit ettirmeyi açıkça yazıyor — kesinlik dili üç
  dilde birden testle pinli.
- **Yayımlanmış tarih düzeltmesi kanalı.** Sunucudaki küçük bir tablo, idarenin
  yıl içinde uzattığı süreleri kurulu sürümlere ulaştırıyor. İstemciye
  salt-okunur ve kullanıcı verisi taşımıyor; geri de çekilebiliyor.
- **Ürün telemetrisi** (`product_events`) — üçüncü taraf analytics SDK'sı
  **yok**. Gün + olay bazında sayaç tutuluyor; kullanıcı düzeyinde olay dizisi
  tutulmuyor. **Serbest metin ve tutar taşıyamaz**: olay adı tip olarak
  kısıtlı ve sunucu bunu bağımsız bir CHECK'le tekrarlıyor. Ayarlardan
  kapatılabiliyor, en fazla 90 gün saklanıyor.

### Fixed
- **Sync artık kaybettiği sürümü silmiyor.** İki cihazda aynı kaydı düzenleyen
  tek bir kullanıcıda, last-write-wins'in kaybettiği uzak sürüm sessizce
  siliniyordu. Kaybeden sürüm artık cihazda karantinaya alınıyor. Bu sürümde
  **çakışma ekranı yok** — görünür çözüm sonraki sürümde.
- **Ebeveyni henüz inmemiş satırlar atlanmıyor, bekletiliyor.** Önceden sessizce
  düşürülüyorlardı.
- **Çıkışta ve hesap silmede bekleyen bildirimler de siliniyor.** Önceden
  yalnız veritabanı temizleniyordu; OS'e teslim edilmiş bir hatırlatma
  hesaptan sonra da patlayabiliyordu.

### Changed
- Yerel veritabanı şeması **v4 → v8**. Her adım tamamen eklemeli: yalnız yeni
  tablo yaratılıyor, mevcut hiçbir satır okunmuyor veya yeniden yazılmıyor.
- Hijyen: `receipt_ocr` git tag'ine pinli (`v0.2.0`), Sentry stable sürümde,
  `export-csv` TR Excel'de sütunlara ayrılıyor (`;` + BOM), her feature flag'in
  ölüm tarihi var ve süresi geçerse CI düşüyor.

> ⚠️ **Bu dosya 1.0.0 ile 1.3.0 arasında eksiktir.** 1.0.1, 1.1.0, 1.2.0 ve
> 1.2.1 mağazaya çıktı ama buraya işlenmedi; aşağıdaki `[Unreleased]` bloğu da
> aslında o sürümlerde çıkmış işleri sayıyor. Geriye dönük doldurmak ayrı bir
> iş — uydurmamak için olduğu gibi bırakıldı.

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
