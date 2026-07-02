// gemini-ocr-fallback
// ─────────────────────────────────────────────────────────────────────────
// Supabase Edge Function that runs Gemini Vision over a receipt image when
// the on-device ML Kit confidence drops below threshold.
//
// ─────────────────────────────────────────────────────────────────────────
// Request:
//   POST  https://<project>.supabase.co/functions/v1/gemini-ocr-fallback
//   Headers:
//     Authorization: Bearer <user JWT>    ← auto-attached by supabase-flutter
//     Content-Type:  application/json
//   Body:
//     { "image_base64": "<...>", "mime_type": "image/jpeg" }
//
// Response (200):
//   {
//     "data": {
//       "raw_text":   "…",
//       "confidence": 0.93,
//       "store_name": "…",
//       "items":      [{ "name": "…", "qty": 1, "unit_price": 1250,
//                        "total_price": 1250 }],
//       "total":      8200,
//       "tax":        700,
//       "currency":   "TRY"
//     },
//     "error": null
//   }
//
// Response (429 — token bucket exhausted):
//   { "data": null,
//     "error": { "code": "RATE_LIMIT", "message": "…", "retry_after": 3600 } }
//
// ─────────────────────────────────────────────────────────────────────────
// Security invariants:
//   1. Resolve auth.uid() from the JWT. Never trust a client-supplied user_id.
//   2. consume_token(uid, 'gemini-ocr', 20, 1) before touching Gemini.
//      20 calls/user/day, refilling 1/hour. Returns 429 on empty bucket.
//   3. GEMINI_API_KEY lives only in Deno.env — never logged, never returned.
//   4. The raw image bytes are never logged; only the decoded byte length is.
// ─────────────────────────────────────────────────────────────────────────

import { corsHeaders } from "../_shared/cors.ts";
import {
  fail,
  getAuthUser,
  json,
  requireEnv,
  UnauthorizedError,
  withCors,
} from "../_shared/runtime.ts";

// deno-lint-ignore no-explicit-any
declare const Deno: any;

const RATE_BUCKET = "gemini-ocr";
const RATE_MAX_TOKENS = 20;
const RATE_REFILL_PER_HOUR = 1;
const MAX_IMAGE_BYTES = 4 * 1024 * 1024; // 4 MiB decoded.
// Model is env-overridable so a future Google model retirement is a
// `supabase secrets set GEMINI_MODEL=…` away — no redeploy. Gemini 1.5 was
// shut down in 2026 (every request 404s); 2.5-flash is the current vision
// model with JSON response support.
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";

interface OcrRequest {
  image_base64?: string;
  mime_type?: string;
}

interface ParsedItem {
  name: string;
  qty: number;
  unit_price: number;
  total_price: number;
}

interface OcrData {
  raw_text: string;
  confidence: number;
  store_name: string | null;
  items: ParsedItem[];
  total: number | null;
  tax: number | null;
  currency: string | null;
}

const PROMPT = [
  "You are a receipt OCR engine. Read the attached receipt image and return",
  "ONLY a compact JSON object (no markdown, no prose) with this exact shape:",
  '{"raw_text": string, "store_name": string|null, "currency": string|null,',
  '"items": [{"name": string, "qty": number, "unit_price": number,',
  '"total_price": number}], "total": number|null, "tax": number|null,',
  '"confidence": number}.',
  "Monetary values are integers in the smallest currency unit (e.g. kuruş,",
  "cents): 12.50 TRY → 1250. confidence is 0..1. Use null when unsure.",
].join(" ");

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return withCors(fail("METHOD_NOT_ALLOWED", "POST required.", 405), corsHeaders);
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

  // Rate limit BEFORE the expensive Gemini call.
  const { data: allowed, error: rlError } = await supabase.rpc("consume_token", {
    p_user_id: userId,
    p_bucket: RATE_BUCKET,
    p_max_tokens: RATE_MAX_TOKENS,
    p_refill_per_hour: RATE_REFILL_PER_HOUR,
  });
  if (rlError) {
    return withCors(fail("DB_ERROR", rlError.message, 500), corsHeaders);
  }
  if (allowed !== true) {
    return withCors(
      fail("RATE_LIMIT", "Daily AI scan limit reached.", 429, {
        retry_after: 3600,
      }),
      corsHeaders,
    );
  }

  let body: OcrRequest;
  try {
    body = (await req.json()) as OcrRequest;
  } catch (_e) {
    return withCors(fail("BAD_REQUEST", "Malformed JSON body.", 400), corsHeaders);
  }
  const imageBase64 = body.image_base64;
  const mimeType = body.mime_type ?? "image/jpeg";
  if (!imageBase64) {
    return withCors(fail("BAD_REQUEST", "image_base64 is required.", 400), corsHeaders);
  }
  // 4 base64 chars encode 3 bytes; cheap size guard without decoding.
  const approxBytes = Math.floor((imageBase64.length * 3) / 4);
  if (approxBytes > MAX_IMAGE_BYTES) {
    return withCors(fail("IMAGE_TOO_LARGE", "Image exceeds 4 MiB.", 413), corsHeaders);
  }

  let apiKey: string;
  try {
    apiKey = requireEnv("GEMINI_API_KEY");
  } catch (_e) {
    return withCors(fail("CONFIG_MISSING", "OCR engine unavailable.", 500), corsHeaders);
  }

  let geminiText: string;
  try {
    geminiText = await callGemini(apiKey, imageBase64, mimeType);
  } catch (e) {
    const message = e instanceof Error ? e.message : "Gemini request failed.";
    return withCors(fail("OCR_FAILED", message, 502), corsHeaders);
  }

  const data = parseGeminiJson(geminiText);
  return withCors(json<OcrData>({ data, error: null }), corsHeaders);
}

async function callGemini(
  apiKey: string,
  imageBase64: string,
  mimeType: string,
): Promise<string> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": apiKey,
    },
    body: JSON.stringify({
      contents: [
        {
          parts: [
            { text: PROMPT },
            { inline_data: { mime_type: mimeType, data: imageBase64 } },
          ],
        },
      ],
      generationConfig: { temperature: 0, responseMimeType: "application/json" },
    }),
  });
  if (!res.ok) {
    // Never surface the upstream body verbatim (may echo the request); a
    // status code is enough for the client to retry or fall back.
    throw new Error(`Gemini HTTP ${res.status}`);
  }
  const payload = await res.json();
  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string") {
    throw new Error("Gemini returned no text candidate.");
  }
  return text;
}

/// Gemini occasionally wraps JSON in ```json fences despite the prompt.
/// Strip them, parse, and coerce into the contract with safe defaults.
export function parseGeminiJson(text: string): OcrData {
  const cleaned = text.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "")
    .trim();
  let raw: Record<string, unknown>;
  try {
    raw = JSON.parse(cleaned) as Record<string, unknown>;
  } catch (_e) {
    // Couldn't parse — hand back the raw text so the parser layer / user can
    // still salvage something, with zero confidence.
    return {
      raw_text: text,
      confidence: 0,
      store_name: null,
      items: [],
      total: null,
      tax: null,
      currency: null,
    };
  }

  const items = Array.isArray(raw.items)
    ? (raw.items as Record<string, unknown>[]).map((it) => ({
      name: String(it.name ?? ""),
      qty: toNumber(it.qty) ?? 1,
      unit_price: toInt(it.unit_price) ?? 0,
      total_price: toInt(it.total_price) ?? 0,
    }))
    : [];

  return {
    raw_text: typeof raw.raw_text === "string" ? raw.raw_text : text,
    confidence: clamp01(toNumber(raw.confidence) ?? 0.9),
    store_name: typeof raw.store_name === "string" ? raw.store_name : null,
    items,
    total: toInt(raw.total),
    tax: toInt(raw.tax),
    currency: typeof raw.currency === "string" ? raw.currency : null,
  };
}

function toNumber(v: unknown): number | null {
  if (typeof v === "number" && !isNaN(v)) return v;
  return null;
}

function toInt(v: unknown): number | null {
  const n = toNumber(v);
  return n === null ? null : Math.round(n);
}

function clamp01(v: number): number {
  return Math.max(0, Math.min(1, v));
}

// Serve only when this module is the entry point — `deno test` imports the
// file and would otherwise spin up a real server.
if (import.meta.main) Deno.serve(handle);
