// Deno tests for gemini-ocr-fallback. Run with:
//   deno test --allow-net --allow-env supabase/functions/__tests__/
//
// These cover the deterministic, no-network paths: method/auth guards and
// the Gemini JSON parser. The Gemini call + rate-limit paths need a live
// stack and are exercised by the Sprint 8.4 smoke test instead.

import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handle, parseGeminiJson } from "../gemini-ocr-fallback/index.ts";

Deno.test("OPTIONS preflight returns CORS headers", async () => {
  const res = await handle(
    new Request("http://x/gemini-ocr-fallback", { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("non-POST is rejected with 405", async () => {
  const res = await handle(
    new Request("http://x/gemini-ocr-fallback", { method: "GET" }),
  );
  assertEquals(res.status, 405);
  const body = await res.json();
  assertEquals(body.error.code, "METHOD_NOT_ALLOWED");
});

Deno.test("missing Authorization header is rejected with 401", async () => {
  const res = await handle(
    new Request("http://x/gemini-ocr-fallback", {
      method: "POST",
      body: JSON.stringify({ image_base64: "abc" }),
    }),
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error.code, "UNAUTHENTICATED");
});

Deno.test("parseGeminiJson handles a clean JSON payload", () => {
  const out = parseGeminiJson(
    '{"raw_text":"BIM","store_name":"BIM","currency":"TRY",' +
      '"items":[{"name":"Süt","qty":2,"unit_price":1250,"total_price":2500}],' +
      '"total":2500,"tax":227,"confidence":0.9}',
  );
  assertEquals(out.store_name, "BIM");
  assertEquals(out.total, 2500);
  assertEquals(out.items.length, 1);
  assertEquals(out.items[0].total_price, 2500);
  assertEquals(out.confidence, 0.9);
});

Deno.test("parseGeminiJson strips ```json fences", () => {
  const out = parseGeminiJson('```json\n{"total":100,"confidence":0.5}\n```');
  assertEquals(out.total, 100);
  assertEquals(out.confidence, 0.5);
});

Deno.test("parseGeminiJson falls back to raw text on garbage", () => {
  const out = parseGeminiJson("not json at all");
  assertEquals(out.confidence, 0);
  assertEquals(out.raw_text, "not json at all");
  assert(out.items.length === 0);
});

Deno.test("parseGeminiJson coerces float money to integer", () => {
  const out = parseGeminiJson('{"total":99.6,"confidence":1.4}');
  assertEquals(out.total, 100); // rounded
  assertEquals(out.confidence, 1); // clamped to 0..1
});
