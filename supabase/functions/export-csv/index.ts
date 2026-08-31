// export-csv
// ─────────────────────────────────────────────────────────────────────────
// Generates a CSV of the caller's expenses and returns a signed download URL.
//
// Request:
//   GET  /functions/v1/export-csv?from_date=YYYY-MM-DD&to_date=YYYY-MM-DD
//        (both query params optional)
//   Headers: Authorization: Bearer <user JWT>
//
// Response (200):
//   { "data": { "url": "https://…", "expires_at": "ISO", "row_count": 42 },
//     "error": null }
//
// Security invariants:
//   1. Resolve auth.uid() from the JWT; the user client applies RLS so the
//      query and the storage upload only touch the caller's data.
//   2. The CSV is written to exports/{user_id}/{timestamp}.csv — the leading
//      path segment is the owner uuid, enforced by the exports-bucket RLS.
// ─────────────────────────────────────────────────────────────────────────

import { corsHeaders } from "../_shared/cors.ts";
import {
  fail,
  getAuthUser,
  json,
  UnauthorizedError,
  withCors,
} from "../_shared/runtime.ts";

// deno-lint-ignore no-explicit-any
declare const Deno: any;

const EXPORTS_BUCKET = "exports";
const SIGNED_URL_TTL_SECONDS = 24 * 60 * 60; // 24h.

// ── Turkish Excel compatibility ────────────────────────────────────────────
// This file is opened by an accountant, in Excel, with a Turkish locale.
// Three things decide whether it lands as a spreadsheet or as one mangled
// column of text:
//
//   * Separator. A tr-TR Excel reads `,` as the DECIMAL mark, so its list
//     separator is `;`. A comma-separated file does not split into columns.
//   * BOM. Without it Excel guesses the encoding and Turkish characters
//     (ı İ ş ğ ç ö ü) come out as mojibake.
//   * CRLF. RFC 4180's line ending, and the one Excel is least surprised by.
const CSV_DELIMITER = ";";
const CSV_NEWLINE = "\r\n";
const UTF8_BOM = "\uFEFF";

interface ExportData {
  url: string;
  expires_at: string;
  row_count: number;
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return withCors(fail("METHOD_NOT_ALLOWED", "GET required.", 405), corsHeaders);
  }

  let userId: string;
  let supabase: Awaited<ReturnType<typeof getAuthUser>>["supabase"];
  try {
    const auth = await getAuthUser(req);
    userId = auth.userId;
    supabase = auth.supabase;
  } catch (e) {
    if (e instanceof UnauthorizedError) {
      return withCors(fail("UNAUTHENTICATED", e.message, 401), corsHeaders);
    }
    return withCors(fail("CONFIG_MISSING", "Edge runtime not configured.", 500), corsHeaders);
  }

  const url = new URL(req.url);
  const fromDate = url.searchParams.get("from_date");
  const toDate = url.searchParams.get("to_date");

  let query = supabase
    .from("expenses")
    .select(
      // `currency` lives on `receipts`, not `expenses`; pull it from the
      // embed and default to TRY for manual (receipt-less) expenses.
      "date, amount, note, category:categories(name), receipt:receipts(store_name, currency)",
    )
    .order("date", { ascending: true });
  if (fromDate) query = query.gte("date", fromDate);
  if (toDate) query = query.lte("date", toDate);

  const { data: rows, error: queryError } = await query;
  if (queryError) {
    return withCors(fail("DB_ERROR", queryError.message, 500), corsHeaders);
  }

  const csv = buildCsv(rows ?? []);
  const objectPath = `${userId}/${Date.now()}.csv`;

  const { error: uploadError } = await supabase.storage
    .from(EXPORTS_BUCKET)
    .upload(objectPath, new Blob([csv], { type: "text/csv; charset=utf-8" }), {
      contentType: "text/csv; charset=utf-8",
      upsert: true,
    });
  if (uploadError) {
    return withCors(fail("STORAGE_ERROR", uploadError.message, 500), corsHeaders);
  }

  const { data: signed, error: signError } = await supabase.storage
    .from(EXPORTS_BUCKET)
    .createSignedUrl(objectPath, SIGNED_URL_TTL_SECONDS);
  if (signError || !signed) {
    return withCors(
      fail("STORAGE_ERROR", signError?.message ?? "Could not sign URL.", 500),
      corsHeaders,
    );
  }

  const expiresAt = new Date(Date.now() + SIGNED_URL_TTL_SECONDS * 1000)
    .toISOString();
  return withCors(
    json<ExportData>({
      data: {
        url: signed.signedUrl,
        expires_at: expiresAt,
        row_count: (rows ?? []).length,
      },
      error: null,
    }),
    corsHeaders,
  );
}

/// Builds the complete CSV file, BOM included, ready to upload verbatim.
///
/// `amount` arrives from Postgres in MINOR UNITS (`expenses.amount` is a
/// bigint of kuruş / cents — the project-wide money invariant). It used to be
/// written straight into the file, so every figure an accountant saw was 100x
/// too large: 12,50 TL exported as `1250`. It is now rendered as a decimal
/// with a Turkish comma, using integer arithmetic only — no `double` ever
/// touches a monetary value.
// deno-lint-ignore no-explicit-any
export function buildCsv(rows: any[]): string {
  const header = ["date", "store", "category", "amount", "currency", "note"];
  const lines = [header.join(CSV_DELIMITER)];
  for (const row of rows) {
    lines.push(
      [
        csvCell(formatDate(row.date)),
        csvText(row.receipt?.store_name ?? ""),
        csvText(row.category?.name ?? ""),
        csvCell(formatMinor(row.amount)),
        csvCell(row.receipt?.currency ?? "TRY"),
        csvText(row.note ?? ""),
      ].join(CSV_DELIMITER),
    );
  }
  return UTF8_BOM + lines.join(CSV_NEWLINE) + CSV_NEWLINE;
}

/// Renders a minor-unit amount as `1234,56`.
///
/// Integer arithmetic on the digit string, so a bigint beyond
/// `Number.MAX_SAFE_INTEGER` cannot silently lose precision on its way through
/// a float — the same reason the Dart side keeps money in `int`.
export function formatMinor(amount: unknown): string {
  const raw = String(amount ?? "0").trim();
  const match = /^(-?)(\d+)$/.exec(raw);
  if (match === null) {
    // Not an integer: the column contract was broken upstream. Pass the value
    // through untouched rather than inventing a number for an accountant.
    return raw;
  }
  const [, sign, digits] = match;
  const padded = digits.padStart(3, "0");
  const major = padded.slice(0, -2).replace(/^0+(?=\d)/, "");
  const minor = padded.slice(-2);
  return `${sign}${major},${minor}`;
}

/// Reduces a timestamp to its calendar date (`2026-05-01`).
///
/// `expenses.date` is a `timestamptz`, so the raw value carries
/// `T00:00:00+00:00` noise that Excel shows as text.
///
/// NOTE: the date part is taken in UTC, which is what this export already did
/// implicitly by printing the raw timestamp. An expense recorded late in the
/// evening Istanbul time therefore lands on the previous day. Which day a
/// document belongs to is an accounting question, not a formatting one — it
/// rides along with D-13 (what the accountant actually needs in the export)
/// rather than being decided here.
export function formatDate(value: unknown): string {
  const s = String(value ?? "");
  const match = /^(\d{4}-\d{2}-\d{2})/.exec(s);
  return match === null ? s : match[1];
}

/// Escapes a free-text cell that a user typed.
///
/// Beyond quoting, this neutralises spreadsheet formula injection: Excel
/// executes a cell beginning with `=`, `+`, `-` or `@`, so a crafted note
/// would run on the accountant's machine when they open the export. The
/// leading apostrophe is Excel's "this is text" marker and is not displayed.
/// Only text columns go through here — amounts are formatted by
/// [formatMinor] and keep their minus sign.
function csvText(value: unknown): string {
  const s = String(value ?? "");
  return csvCell(/^[=+\-@]/.test(s) ? `'${s}` : s);
}

function csvCell(value: unknown): string {
  const s = String(value ?? "");
  if (/[";\r\n]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

if (import.meta.main) Deno.serve(handle);
