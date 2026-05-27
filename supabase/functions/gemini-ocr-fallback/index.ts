// gemini-ocr-fallback
// ─────────────────────────────────────────────────────────────────────────
// Supabase Edge Function that runs Gemini Vision over a receipt image
// when the on-device ML Kit confidence drops below the threshold.
//
// **Status:** placeholder. Sprint 2.2 ships the client wiring; this file
// is filled in and deployed in Sprint 8. The shape below is the contract
// the Flutter `GeminiOCRDataSource` expects so the two stay in sync.
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
// Security invariants (Sprint 8 must enforce):
//   1. Validate the JWT and resolve `auth.uid()`. Never trust a
//      client-supplied user_id.
//   2. Call `consume_token(uid, 'gemini', max => 20, refill_per_hour => 1)`
//      Postgres function before touching Gemini. Return 429 on false.
//   3. Read `GEMINI_API_KEY` from `Deno.env.get` only; never log it.
//   4. Never log the raw image bytes — capture only image size + hash for
//      observability.

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'

serve(async (req) => {
  // TODO(sprint-8): JWT validation via supabase.auth.getUser(req).
  // TODO(sprint-8): consume_token() rate limit check.
  // TODO(sprint-8): Decode image_base64, call Gemini Vision REST endpoint
  //                 with GEMINI_API_KEY from Deno.env.
  // TODO(sprint-8): Parse Gemini response → contract above, return JSON.

  return new Response(
    JSON.stringify({
      data: null,
      error: {
        code: 'NOT_IMPLEMENTED',
        message:
          'gemini-ocr-fallback is a Sprint 2.2 placeholder. Deployment ' +
          'lands in Sprint 8 — until then ML Kit is the only OCR path.',
      },
    }),
    {
      status: 501,
      headers: { 'Content-Type': 'application/json' },
    },
  )
})
