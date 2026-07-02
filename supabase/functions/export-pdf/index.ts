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
  type PDFFont,
  StandardFonts,
  rgb,
} from "https://esm.sh/pdf-lib@1.17.1";
// fontkit ships a CommonJS default export but its .d.ts declares none, so a
// default import fails type-checking. Import the namespace and unwrap the
// runtime default.
import * as fontkitNs from "https://esm.sh/@pdf-lib/fontkit@1.1.1";

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

// Runtime fontkit object (default export under esm.sh CJS interop).
// deno-lint-ignore no-explicit-any
const fontkit: any = (fontkitNs as any).default ?? fontkitNs;

const EXPORTS_BUCKET = "exports";
const SIGNED_URL_TTL_SECONDS = 24 * 60 * 60; // 24h.

// Unicode font (Roboto) so Turkish letters (ı İ ş ğ) and German umlauts render
// exactly. The built-in Helvetica only covers WinAnsi and would otherwise drop
// Turkish-specific glyphs. Pinned, complete TTFs (full Latin + Latin Extended).
const FONT_REGULAR_URL =
  "https://cdn.jsdelivr.net/npm/@expo-google-fonts/roboto@0.2.3/Roboto_400Regular.ttf";
const FONT_BOLD_URL =
  "https://cdn.jsdelivr.net/npm/@expo-google-fonts/roboto@0.2.3/Roboto_700Bold.ttf";

/// Font bytes are fetched once per isolate (cold start) and reused. Cached on
/// success only, so a transient network failure is retried on the next call.
let _fontBytes: [Uint8Array, Uint8Array] | null = null;

/// Loader signature so tests can inject deterministic / failing fonts.
export type FontLoader = () => Promise<[Uint8Array, Uint8Array]>;

async function loadUnicodeFontBytes(): Promise<[Uint8Array, Uint8Array]> {
  if (_fontBytes) return _fontBytes;
  const fetchTtf = async (url: string): Promise<Uint8Array> => {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`font fetch ${res.status}`);
    return new Uint8Array(await res.arrayBuffer());
  };
  const bytes: [Uint8Array, Uint8Array] = [
    await fetchTtf(FONT_REGULAR_URL),
    await fetchTtf(FONT_BOLD_URL),
  ];
  _fontBytes = bytes;
  return bytes;
}

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
      // `currency` lives on `receipts`, not `expenses`; pull it from the
      // embed and default to TRY for manual (receipt-less) expenses.
      "date, amount, note, category:categories(name), receipt:receipts(store_name, currency)",
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
    currency: String(row.receipt?.currency ?? "TRY"),
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

/// Render the report model to PDF bytes. Paginates at 32 rows per page.
///
/// Embeds a Unicode font (Roboto) so Turkish + German render exactly. If the
/// font can't be loaded (e.g. transient network failure at cold start), it
/// falls back to the built-in Helvetica with Turkish-only transliteration so
/// the export never fails. [fontLoader] is injectable for tests.
export async function renderPdf(
  model: ReportModel,
  fontLoader: FontLoader = loadUnicodeFontBytes,
): Promise<Uint8Array> {
  const doc = await PDFDocument.create();

  let font: PDFFont;
  let bold: PDFFont;
  let sanitize: (s: string) => string;
  try {
    doc.registerFontkit(fontkit);
    const [regularBytes, boldBytes] = await fontLoader();
    font = await doc.embedFont(regularBytes, { subset: true });
    bold = await doc.embedFont(boldBytes, { subset: true });
    sanitize = (s) => s; // Unicode font — no transliteration needed.
  } catch (_) {
    font = await doc.embedFont(StandardFonts.Helvetica);
    bold = await doc.embedFont(StandardFonts.HelveticaBold);
    sanitize = winAnsiSafe; // WinAnsi fallback — map Turkish-only glyphs.
  }

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
    page.drawText(trunc(date, 14, sanitize), {
      x: cols[0],
      y,
      size: 9,
      font: f,
      color,
    });
    page.drawText(trunc(store, 26, sanitize), {
      x: cols[1],
      y,
      size: 9,
      font: f,
      color,
    });
    page.drawText(trunc(category, 20, sanitize), {
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

function trunc(
  s: string,
  max: number,
  sanitize: (s: string) => string,
): string {
  const safe = sanitize(s);
  return safe.length > max ? `${safe.slice(0, max - 1)}...` : safe;
}

/// WinAnsi (CP1252) — used only by the Helvetica fallback path — covers German
/// umlauts (ä ö ü ß) but NOT the Turkish-specific letters ı İ ş ğ. When the
/// Unicode font (Roboto) can't be loaded, we transliterate those few glyphs so
/// user data (store / category names) never crashes PDF generation. The normal
/// path embeds Roboto and renders Turkish exactly — no transliteration.
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
