// apple-register
// ─────────────────────────────────────────────────────────────────────────
// Exchanges the native "Sign in with Apple" authorizationCode for a refresh
// token and stores it (service_role) so delete-account can later revoke the
// Apple grant — required by App Store Guideline 5.1.1(v).
//
// Request:
//   POST  /functions/v1/apple-register
//   Headers: Authorization: Bearer <user JWT>
//   Body:   { "code": "<authorizationCode from the Apple credential>" }
//
// Response (200): { "data": { "linked": true | false }, "error": null }
//
// The client calls this right after a successful Apple sign-in. Apple returns a
// fresh, single-use code on every sign-in, so the stored token is refreshed
// each time (upsert on user_id).
// ─────────────────────────────────────────────────────────────────────────

import { corsHeaders } from "../_shared/cors.ts";
import {
  fail,
  getAdminClient,
  getAuthUser,
  json,
  UnauthorizedError,
  withCors,
} from "../_shared/runtime.ts";
import { exchangeAuthCode } from "../_shared/apple.ts";

// deno-lint-ignore no-explicit-any
declare const Deno: any;

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return withCors(
      fail("METHOD_NOT_ALLOWED", "POST required.", 405),
      corsHeaders,
    );
  }

  let userId: string;
  try {
    const auth = await getAuthUser(req);
    userId = auth.userId;
  } catch (e) {
    if (e instanceof UnauthorizedError) {
      return withCors(fail("UNAUTHENTICATED", e.message, 401), corsHeaders);
    }
    return withCors(
      fail("CONFIG_MISSING", "Edge runtime not configured.", 500),
      corsHeaders,
    );
  }

  let body: { code?: string };
  try {
    body = (await req.json()) as { code?: string };
  } catch (_e) {
    return withCors(
      fail("BAD_REQUEST", "Malformed JSON body.", 400),
      corsHeaders,
    );
  }
  const code = body.code?.trim();
  if (!code) {
    return withCors(
      fail("BAD_REQUEST", "Missing authorization code.", 400),
      corsHeaders,
    );
  }

  let refreshToken: string | null;
  try {
    refreshToken = await exchangeAuthCode(code);
  } catch (e) {
    // Misconfigured Apple secrets or a rejected code. The client treats this
    // as non-fatal and retries on the next sign-in.
    return withCors(
      fail("APPLE_EXCHANGE_FAILED", (e as Error).message, 502),
      corsHeaders,
    );
  }
  if (!refreshToken) {
    // Apple returned no refresh token — nothing to revoke later. Success so
    // sign-in is never blocked.
    return withCors(
      json({ data: { linked: false }, error: null }),
      corsHeaders,
    );
  }

  const admin = getAdminClient();
  const { error } = await admin
    .from("apple_credentials")
    .upsert(
      { user_id: userId, refresh_token: refreshToken },
      { onConflict: "user_id" },
    );
  if (error) {
    return withCors(fail("STORE_FAILED", error.message, 500), corsHeaders);
  }

  return withCors(json({ data: { linked: true }, error: null }), corsHeaders);
}

if (import.meta.main) Deno.serve(handle);
