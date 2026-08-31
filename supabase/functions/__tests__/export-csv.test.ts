// Deno tests for export-csv. Run with:
//   deno test --allow-env supabase/functions/__tests__/

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildCsv,
  formatDate,
  formatMinor,
  handle,
} from "../export-csv/index.ts";

Deno.test("non-GET is rejected with 405", async () => {
  const res = await handle(
    new Request("http://x/export-csv", { method: "POST" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("missing Authorization header is rejected with 401", async () => {
  const res = await handle(
    new Request("http://x/export-csv", { method: "GET" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error.code, "UNAUTHENTICATED");
});

// ── The file has to open as a spreadsheet in a Turkish Excel ───────────────

Deno.test("the file starts with a UTF-8 BOM", () => {
  const csv = buildCsv([]);
  assertEquals(csv.charCodeAt(0), 0xfeff);
});

Deno.test("rows are semicolon separated and CRLF terminated", () => {
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: 1250,
      note: "öğle yemeği",
      category: { name: "Restoran" },
      receipt: { store_name: "Kebapçı", currency: "TRY" },
    },
  ]);
  const lines = csv.slice(1).split("\r\n");

  assertEquals(lines[0], "date;store;category;amount;currency;note");
  assertEquals(lines[1], "2026-05-01;Kebapçı;Restoran;12,50;TRY;öğle yemeği");
  // Trailing newline: the last row is terminated, not left dangling.
  assertEquals(lines[2], "");
  assert(!csv.includes("\n\n"), "no blank line between rows");
});

Deno.test("Turkish characters survive verbatim", () => {
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: 100,
      note: "ışık İĞÜŞÇÖ ğüşçö",
      category: null,
      receipt: null,
    },
  ]);
  assertStringIncludes(csv, "ışık İĞÜŞÇÖ ğüşçö");
});

// ── Money: minor units are kuruş, not lira ─────────────────────────────────

Deno.test("amounts are rendered from minor units with a Turkish comma", () => {
  // Regression guard: these used to be written raw, so 12,50 TL reached the
  // accountant as `1250` — every figure 100x too large.
  assertEquals(formatMinor(1250), "12,50");
  assertEquals(formatMinor(5), "0,05");
  assertEquals(formatMinor(50), "0,50");
  assertEquals(formatMinor(0), "0,00");
  assertEquals(formatMinor(100), "1,00");
  assertEquals(formatMinor(123456789), "1234567,89");
});

Deno.test("negative amounts keep their sign", () => {
  assertEquals(formatMinor(-1250), "-12,50");
  assertEquals(formatMinor(-5), "-0,05");
});

Deno.test("a bigint past MAX_SAFE_INTEGER keeps every digit", () => {
  // Postgres bigint can exceed what a JS number holds exactly. The formatter
  // works on the digit string, so no precision is lost to a float.
  assertEquals(
    formatMinor("92233720368547758"),
    "922337203685477,58",
  );
});

Deno.test("a non-integer amount is passed through, not invented", () => {
  assertEquals(formatMinor("n/a"), "n/a");
  // `expenses.amount` is NOT NULL, so this is belt-and-braces: a missing
  // value reads as zero rather than as an empty cell.
  assertEquals(formatMinor(null), "0,00");
});

// ── Dates ──────────────────────────────────────────────────────────────────

Deno.test("timestamps are reduced to a calendar date", () => {
  assertEquals(formatDate("2026-05-01T21:30:00+00:00"), "2026-05-01");
  assertEquals(formatDate("2026-05-01"), "2026-05-01");
  assertEquals(formatDate(null), "");
});

// ── Escaping ───────────────────────────────────────────────────────────────

Deno.test("cells containing the separator or a quote are quoted", () => {
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: 100,
      note: 'has; semicolon and "quote"',
      category: null,
      receipt: null,
    },
  ]);
  assertStringIncludes(csv, '"has; semicolon and ""quote"""');
});

Deno.test("a comma no longer forces quoting", () => {
  // With `;` as the separator, a comma is ordinary text — and quoting it
  // would be actively wrong for decimal amounts.
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: 1250,
      note: "a, b",
      category: null,
      receipt: null,
    },
  ]);
  assertStringIncludes(csv, ";12,50;TRY;a, b");
});

Deno.test("a newline inside a note is quoted, not left to break the row", () => {
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: 100,
      note: "line one\nline two",
      category: null,
      receipt: null,
    },
  ]);
  assertStringIncludes(csv, '"line one\nline two"');
});

Deno.test("formula injection in a text cell is neutralised", () => {
  // Excel executes a cell starting with = + - or @. This export is opened on
  // an accountant's machine, so a crafted note must not run there.
  for (const payload of ["=1+1", "+1", "-1+1", "@SUM(A1)", "=cmd|'/c calc'!A0"]) {
    const csv = buildCsv([
      {
        date: "2026-05-01",
        amount: 100,
        note: payload,
        category: { name: payload },
        receipt: { store_name: payload, currency: "TRY" },
      },
    ]);
    const row = csv.slice(1).split("\r\n")[1];
    const cells = row.split(";");
    assert(
      !cells.some((c) => /^[=+\-@]/.test(c)),
      `unescaped formula cell for payload ${payload}: ${row}`,
    );
  }
});

Deno.test("a negative amount is not treated as a formula", () => {
  // The guard applies to text columns only; the amount keeps its minus sign.
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: -1250,
      note: "",
      category: null,
      receipt: null,
    },
  ]);
  assertStringIncludes(csv, ";-12,50;TRY;");
});

Deno.test("an empty result still produces a usable header", () => {
  const csv = buildCsv([]);
  assertEquals(csv, "﻿date;store;category;amount;currency;note\r\n");
});
