// export-pdf
// ─────────────────────────────────────────────────────────────────────────
// Generates a monthly spending-report PDF of the caller's expenses and returns
// a signed download URL. Sibling of `export-csv`, same envelope + storage path.
//
// Request:
//   GET  /functions/v1/export-pdf?from_date=YYYY-MM-DD&to_date=YYYY-MM-DD
//        (both query params optional; if omitted, covers the current month)
//   Headers: Authorization: Bearer <user JWT>
//
// Response (200):
//   { "data": { "url": "https://…", "expires_at": "ISO", "row_count": 42 },
//     "error": null }
//
// Security invariants (identical to export-csv):
//   1. Resolve auth.uid() from the JWT; the user client applies RLS so the
//      query and the storage upload only touch the caller's data.
//   2. The PDF is written to exports/{user_id}/{timestamp}.pdf — the leading
//      path segment is the owner uuid, enforced by the exports-bucket RLS.
// ─────────────────────────────────────────────────────────────────────────

import {
  PDFDocument,
  StandardFonts,
  rgb,
} from "https://esm.sh/pdf-lib@1.17.1";

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

interface ExportData {
  url: string;
  expires_at: string;
  row_count: number;
}

/// A single line in the report — already display-formatted.
export interface ReportLine {
  date: string;
  store: string;
  category: string;
  amountMinor: number;
  currency: string;
}

/// Pure, testable report model derived from raw expense rows.
export interface ReportModel {
  fromDate: string;
  toDate: string;
  lines: ReportLine[];
  totalMinor: number;
  currency: string;
  rowCount: number;
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return withCors(
      fail("METHOD_NOT_ALLOWED", "GET required.", 405),
      corsHeaders,
    );
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
    return withCors(
      fail("CONFIG_MISSING", "Edge runtime not configured.", 500),
      corsHeaders,
    );
  }

  const url = new URL(req.url);
  const { fromDate, toDate } = resolvePeriod(
    url.searchParams.get("from_date"),
    url.searchParams.get("to_date"),
  );

  const { data: rows, error: queryError } = await supabase
    .from("expenses")
    .select(
      "date, amount, currency, note, category:categories(name), receipt:receipts(store_name)",
    )
    .gte("date", fromDate)
    .lte("date", toDate)
    .order("date", { ascending: true });
  if (queryError) {
    return withCors(fail("DB_ERROR", queryError.message, 500), corsHeaders);
  }

  const model = buildReportModel(rows ?? [], fromDate, toDate);
  const pdfBytes = await renderPdf(model);
  const objectPath = `${userId}/${Date.now()}.pdf`;

  const { error: uploadError } = await supabase.storage
    .from(EXPORTS_BUCKET)
    .upload(objectPath, pdfBytes, {
      contentType: "application/pdf",
      upsert: true,
    });
  if (uploadError) {
    return withCors(
      fail("STORAGE_ERROR", uploadError.message, 500),
      corsHeaders,
    );
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
        row_count: model.rowCount,
      },
      error: null,
    }),
    corsHeaders,
  );
}

/// Default the period to the current calendar month when not supplied.
export function resolvePeriod(
  from: string | null,
  to: string | null,
  now: Date = new Date(),
): { fromDate: string; toDate: string } {
  if (from && to) return { fromDate: from, toDate: to };
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth();
  const first = new Date(Date.UTC(year, month, 1));
  const last = new Date(Date.UTC(year, month + 1, 0));
  return {
    fromDate: from ?? isoDate(first),
    toDate: to ?? isoDate(last),
  };
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/// Transform raw rows into a display-ready, summed report model.
/// Money stays in minor units (kuruş/cents) — never floats.
// deno-lint-ignore no-explicit-any
export function buildReportModel(
  rows: any[],
  fromDate: string,
  toDate: string,
): ReportModel {
  const lines: ReportLine[] = rows.map((row) => ({
    date: String(row.date ?? ""),
    store: String(row.receipt?.store_name ?? "—"),
    category: String(row.category?.name ?? "—"),
    amountMinor: Number(row.amount ?? 0),
    currency: String(row.currency ?? ""),
  }));
  const totalMinor = lines.reduce((sum, l) => sum + l.amountMinor, 0);
  const currency = lines.length > 0 ? lines[0].currency : "";
  return {
    fromDate,
    toDate,
    lines,
    totalMinor,
    currency,
    rowCount: lines.length,
  };
}

/// Format minor units (e.g. 1250) as a major-unit string (e.g. "12.50").
export function formatMinor(amountMinor: number): string {
  const sign = amountMinor < 0 ? "-" : "";
  const abs = Math.abs(amountMinor);
  const major = Math.floor(abs / 100);
  const minor = (abs % 100).toString().padStart(2, "0");
  return `${sign}${major}.${minor}`;
}

/// Render the report model to PDF bytes. Paginates at 40 rows per page.
export async function renderPdf(model: ReportModel): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);

  const pageWidth = 595; // A4 portrait points.
  const pageHeight = 842;
  const margin = 48;
  const rowHeight = 18;
  const rowsPerPage = 32;
  const ink = rgb(0.1, 0.1, 0.12);
  const muted = rgb(0.45, 0.45, 0.5);

  const cols = [margin, margin + 90, margin + 250, margin + 380];

  let page = doc.addPage([pageWidth, pageHeight]);
  let y = pageHeight - margin;

  const drawHeader = () => {
    page.drawText("SmartSpend", {
      x: margin,
      y,
      size: 20,
      font: bold,
      color: ink,
    });
    y -= 24;
    page.drawText(`Spending report  ${model.fromDate} - ${model.toDate}`, {
      x: margin,
      y,
      size: 11,
      font,
      color: muted,
    });
    y -= 28;
    drawRow("Date", "Store", "Category", "Amount", bold, ink);
    y -= 6;
    page.drawLine({
      start: { x: margin, y },
      end: { x: pageWidth - margin, y },
      thickness: 0.5,
      color: muted,
    });
    y -= rowHeight;
  };

  const drawRow = (
    date: string,
    store: string,
    category: string,
    amount: string,
    f = font,
    color = ink,
  ) => {
    page.drawText(trunc(date, 14), { x: cols[0], y, size: 9, font: f, color });
    page.drawText(trunc(store, 26), { x: cols[1], y, size: 9, font: f, color });
    page.drawText(trunc(category, 20), {
      x: cols[2],
      y,
      size: 9,
      font: f,
      color,
    });
    page.drawText(amount, { x: cols[3], y, size: 9, font: f, color });
  };

  drawHeader();

  let rowsOnPage = 0;
  for (const line of model.lines) {
    if (rowsOnPage >= rowsPerPage) {
      page = doc.addPage([pageWidth, pageHeight]);
      y = pageHeight - margin;
      drawHeader();
      rowsOnPage = 0;
    }
    drawRow(
      line.date,
      line.store,
      line.category,
      `${formatMinor(line.amountMinor)} ${line.currency}`,
    );
    y -= rowHeight;
    rowsOnPage += 1;
  }

  if (model.lines.length === 0) {
    page.drawText("No expenses in this period.", {
      x: margin,
      y,
      size: 10,
      font,
      color: muted,
    });
    y -= rowHeight;
  }

  y -= 8;
  page.drawLine({
    start: { x: margin, y },
    end: { x: pageWidth - margin, y },
    thickness: 0.5,
    color: muted,
  });
  y -= 22;
  page.drawText("Total", { x: cols[2], y, size: 11, font: bold, color: ink });
  page.drawText(
    `${formatMinor(model.totalMinor)} ${model.currency}`,
    { x: cols[3], y, size: 11, font: bold, color: ink },
  );

  return doc.save();
}

function trunc(s: string, max: number): string {
  const safe = winAnsiSafe(s);
  return safe.length > max ? `${safe.slice(0, max - 1)}...` : safe;
}

/// The built-in Helvetica font encodes WinAnsi (CP1252), which covers German
/// umlauts (ä ö ü ß) but NOT the Turkish-specific letters ı İ ş ğ. We
/// transliterate those few glyphs so user data (store / category names) never
/// crashes PDF generation. Future improvement: embed a Unicode TrueType font
/// via `@pdf-lib/fontkit` to render Turkish exactly.
const _winAnsiMap: Record<string, string> = {
  "ı": "i",
  "İ": "I",
  "ş": "s",
  "Ş": "S",
  "ğ": "g",
  "Ğ": "G",
};

export function winAnsiSafe(s: string): string {
  return s.replace(/[ıİşŞğĞ]/g, (ch) => _winAnsiMap[ch] ?? ch);
}

if (import.meta.main) Deno.serve(handle);
