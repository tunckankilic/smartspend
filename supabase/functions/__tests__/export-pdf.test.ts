// Deno tests for export-pdf. Run with:
//   deno test --allow-net --allow-env supabase/functions/__tests__/

import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildReportModel,
  formatMinor,
  handle,
  renderPdf,
  resolvePeriod,
  winAnsiSafe,
} from "../export-pdf/index.ts";

Deno.test("non-GET is rejected with 405", async () => {
  const res = await handle(
    new Request("http://x/export-pdf", { method: "POST" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("missing Authorization header is rejected with 401", async () => {
  const res = await handle(
    new Request("http://x/export-pdf", { method: "GET" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error.code, "UNAUTHENTICATED");
});

Deno.test("resolvePeriod uses given dates when both present", () => {
  const p = resolvePeriod("2026-05-01", "2026-05-31");
  assertEquals(p, { fromDate: "2026-05-01", toDate: "2026-05-31" });
});

Deno.test("resolvePeriod defaults to the current UTC month", () => {
  const now = new Date(Date.UTC(2026, 1, 15)); // 2026-02-15.
  const p = resolvePeriod(null, null, now);
  assertEquals(p, { fromDate: "2026-02-01", toDate: "2026-02-28" });
});

Deno.test("formatMinor renders minor units as major with two decimals", () => {
  assertEquals(formatMinor(1250), "12.50");
  assertEquals(formatMinor(5), "0.05");
  assertEquals(formatMinor(0), "0.00");
  assertEquals(formatMinor(-1299), "-12.99");
});

Deno.test("buildReportModel sums amounts and maps nested fields", () => {
  const model = buildReportModel(
    [
      {
        date: "2026-05-01",
        amount: 1250,
        currency: "TRY",
        note: "lunch",
        category: { name: "Restoran" },
        receipt: { store_name: "Kebapçı" },
      },
      {
        date: "2026-05-02",
        amount: 750,
        currency: "TRY",
        note: null,
        category: null,
        receipt: null,
      },
    ],
    "2026-05-01",
    "2026-05-31",
  );
  assertEquals(model.rowCount, 2);
  assertEquals(model.totalMinor, 2000);
  assertEquals(model.currency, "TRY");
  assertEquals(model.lines[0].store, "Kebapçı");
  assertEquals(model.lines[0].category, "Restoran");
  assertEquals(model.lines[1].store, "—");
  assertEquals(model.lines[1].category, "—");
});

Deno.test("buildReportModel handles an empty period", () => {
  const model = buildReportModel([], "2026-05-01", "2026-05-31");
  assertEquals(model.rowCount, 0);
  assertEquals(model.totalMinor, 0);
});

Deno.test("winAnsiSafe transliterates Turkish-only letters, keeps umlauts", () => {
  // ı İ ş Ş ğ Ğ are not in WinAnsi → transliterated.
  assertEquals(winAnsiSafe("Kebapçı Şişğı"), "Kebapçi Sisgi");
  // German umlauts ARE in WinAnsi → left untouched.
  assertEquals(winAnsiSafe("Müller Bäckerei"), "Müller Bäckerei");
});

Deno.test("renderPdf produces a non-empty PDF (Unicode font path)", async () => {
  const model = buildReportModel(
    [
      {
        date: "2026-05-01",
        amount: 1250,
        currency: "TRY",
        note: "lunch",
        category: { name: "Restoran" },
        receipt: { store_name: "Kebapçı Şişğı" }, // Turkish-only glyphs.
      },
    ],
    "2026-05-01",
    "2026-05-31",
  );
  // Real loader fetches Roboto; Turkish glyphs render without transliteration.
  const bytes = await renderPdf(model);
  // PDF files start with the "%PDF" magic bytes.
  const header = new TextDecoder().decode(bytes.slice(0, 4));
  assertStringIncludes(header, "%PDF");
});

Deno.test("renderPdf falls back to Helvetica when the font can't load", async () => {
  const model = buildReportModel(
    [
      {
        date: "2026-05-01",
        amount: 1250,
        currency: "TRY",
        note: "lunch",
        category: { name: "Restoran" },
        receipt: { store_name: "Kebapçı Şişğı" },
      },
    ],
    "2026-05-01",
    "2026-05-31",
  );
  // Injected loader fails → fallback path must still produce a valid PDF
  // (Turkish glyphs transliterated, never a crash).
  const bytes = await renderPdf(model, () => {
    throw new Error("offline");
  });
  const header = new TextDecoder().decode(bytes.slice(0, 4));
  assertStringIncludes(header, "%PDF");
});
