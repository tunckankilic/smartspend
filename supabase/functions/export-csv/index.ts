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
    .upload(objectPath, new Blob([csv], { type: "text/csv" }), {
      contentType: "text/csv",
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

// deno-lint-ignore no-explicit-any
export function buildCsv(rows: any[]): string {
  const header = ["date", "store", "category", "amount", "currency", "note"];
  const lines = [header.join(",")];
  for (const row of rows) {
    const store = row.receipt?.store_name ?? "";
    const category = row.category?.name ?? "";
    lines.push(
      [
        csvCell(row.date),
        csvCell(store),
        csvCell(category),
        csvCell(row.amount),
        csvCell(row.receipt?.currency ?? "TRY"),
        csvCell(row.note ?? ""),
      ].join(","),
    );
  }
  return lines.join("\n");
}

function csvCell(value: unknown): string {
  const s = String(value ?? "");
  if (/[",\n]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

if (import.meta.main) Deno.serve(handle);
