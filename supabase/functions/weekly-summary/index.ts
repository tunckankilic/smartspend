// weekly-summary
// ─────────────────────────────────────────────────────────────────────────
// Supabase Edge Function that builds a 7-day spend summary for the
// authenticated user.
//
// **Status:** Sprint 6 skeleton. **DO NOT DEPLOY** from this branch —
// Sprint 8 wires:
//   * `pg_cron` job that fires this every Sunday at 09:00 user-local,
//   * a `notifications_outbox` table the function writes into,
//   * an APNs/FCM fan-out worker (or a `flutter_local_notifications`
//     poll on next app open).
//
// The shape below is what the Sprint 6 client expects so the two stay
// in sync.
//
// ─────────────────────────────────────────────────────────────────────────
// Request:
//   POST  https://<project>.supabase.co/functions/v1/weekly-summary
//   Headers:
//     Authorization: Bearer <user JWT>    ← auto-attached by supabase-flutter
//     Content-Type:  application/json
//   Body:
//     { "now": "2026-05-31T00:00:00Z" }   ← optional; defaults to server now
//
// Response (200):
//   {
//     "data": {
//       "currency":      "TRY",
//       "total_minor":   234050,
//       "expense_count": 18,
//       "by_category":   { "1": 56000, "3": 18020, "7": 160030 },
//       "window_start":  "2026-05-24T00:00:00Z",
//       "window_end":    "2026-05-31T00:00:00Z"
//     },
//     "error": null
//   }
//
// Response (401 — missing / invalid JWT):
//   { "data": null,
//     "error": { "code": "UNAUTHENTICATED", "message": "Sign in required." } }
//
// ─────────────────────────────────────────────────────────────────────────
// Security invariants (Sprint 8 must enforce):
//   1. Validate the JWT and resolve `auth.uid()`. Never trust a
//      client-supplied `user_id`.
//   2. Use the user's JWT when constructing the Postgrest client — that
//      way RLS policies on `expenses` filter rows naturally.
//   3. service_role is forbidden from this code path.
// ─────────────────────────────────────────────────────────────────────────

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Deno globals — declared loosely so this file passes the workspace
// `flutter analyze` even when Deno's type info isn't available. The
// real type imports live in `import_map.json` (Sprint 8).
// deno-lint-ignore no-explicit-any
declare const Deno: any;

interface WeeklySummaryRequest {
  now?: string; // ISO-8601; defaults to server clock.
}

interface WeeklySummaryData {
  currency: string;
  total_minor: number;
  expense_count: number;
  by_category: Record<string, number>;
  window_start: string;
  window_end: string;
}

interface EdgeResponse<T> {
  data: T | null;
  error: { code: string; message: string } | null;
}

function json<T>(body: EdgeResponse<T>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function bad(code: string, message: string, status: number): Response {
  return json({ data: null, error: { code, message } }, status);
}

// Deno.serve is the Sprint 8 deploy entry-point; Sprint 6 keeps the
// handler exported so unit tests (Deno test) can invoke it directly.
export async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return bad("METHOD_NOT_ALLOWED", "POST required.", 405);
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return bad("UNAUTHENTICATED", "Sign in required.", 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    return bad("CONFIG_MISSING", "Edge runtime not configured.", 500);
  }

  // Construct the client with the *user's* JWT so RLS does the row
  // filtering. service_role would bypass RLS — forbidden here.
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return bad("UNAUTHENTICATED", "Invalid session.", 401);
  }

  // Parse the optional `now` knob so cron jobs can backfill historical
  // windows during testing without server-clock surgery.
  let payload: WeeklySummaryRequest = {};
  try {
    if (req.headers.get("content-length") !== "0") {
      payload = (await req.json()) as WeeklySummaryRequest;
    }
  } catch (_e) {
    // ignore: empty body is fine, malformed body falls through to
    // server-now defaulting.
  }

  const nowUtc = payload.now ? new Date(payload.now) : new Date();
  if (isNaN(nowUtc.getTime())) {
    return bad("BAD_REQUEST", "Invalid 'now' timestamp.", 400);
  }
  const windowEnd = new Date(
    Date.UTC(nowUtc.getUTCFullYear(), nowUtc.getUTCMonth(), nowUtc.getUTCDate()),
  );
  const windowStart = new Date(windowEnd.getTime() - 7 * 24 * 60 * 60 * 1000);

  // RLS on `expenses` restricts the query to the caller's rows.
  const { data: rows, error: queryError } = await supabase
    .from("expenses")
    // `currency` lives on `receipts`, not `expenses`; read it from the embed.
    .select("amount, category_id, receipt:receipts(currency)")
    .gte("date", windowStart.toISOString())
    .lt("date", windowEnd.toISOString());
  if (queryError) {
    return bad("DB_ERROR", queryError.message, 500);
  }

  // Aggregate in memory — server-side `group by` would also work but
  // costs an extra round-trip with PostgREST. The week's row count is
  // bounded (≤ a few hundred for a heavy user), so this is fine.
  let total = 0;
  let count = 0;
  const byCategory: Record<string, number> = {};
  const currencyVotes: Record<string, number> = {};
  for (const row of rows ?? []) {
    const amount = (row as { amount: number }).amount ?? 0;
    const categoryId = (row as { category_id: string | number }).category_id;
    const currency =
      (row as { receipt?: { currency?: string } }).receipt?.currency ?? "TRY";
    total += amount;
    count += 1;
    const key = String(categoryId);
    byCategory[key] = (byCategory[key] ?? 0) + amount;
    currencyVotes[currency] = (currencyVotes[currency] ?? 0) + 1;
  }
  const currency = Object.entries(currencyVotes)
    .sort((a, b) => b[1] - a[1])[0]?.[0] ?? "TRY";

  const data: WeeklySummaryData = {
    currency,
    total_minor: total,
    expense_count: count,
    by_category: byCategory,
    window_start: windowStart.toISOString(),
    window_end: windowEnd.toISOString(),
  };
  return json({ data, error: null });
}

// Sprint 8 deploy entrypoint — Sprint 6 commented out so a stray
// `supabase functions deploy` from this branch can't accidentally
// publish an unfinished function. Uncomment together with the pg_cron
// + outbox migration in Sprint 8.
// Deno.serve(handle);
