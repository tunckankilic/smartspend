// Shared runtime helpers for Edge Functions: response envelopes, JWT
// verification, and admin-client construction.
//
// Security invariants (every function depends on these):
//   1. `getAuthUser` resolves the caller from their JWT — never trust a
//      client-supplied user_id.
//   2. The *user* client (built from the caller's JWT) is what touches
//      user-owned tables, so RLS filters rows naturally.
//   3. The *admin* client (service_role) bypasses RLS and is reserved for
//      privileged operations (deleting an auth user, listing storage objects
//      across a user's tree). It is NEVER returned to or logged for clients.

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

// Deno globals — declared loosely so this file passes the workspace
// `flutter analyze`/editor tooling even without Deno's type info present.
// deno-lint-ignore no-explicit-any
declare const Deno: any;

export interface EdgeResponse<T> {
  data: T | null;
  error: { code: string; message: string; retry_after?: number } | null;
}

export function json<T>(body: EdgeResponse<T>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      // CORS headers are merged in by callers via `withCors`.
    },
  });
}

export function fail(
  code: string,
  message: string,
  status: number,
  extra: Record<string, unknown> = {},
): Response {
  return json({ data: null, error: { code, message, ...extra } }, status);
}

/// Merge CORS headers onto an existing Response without rebuilding the body.
export function withCors(
  res: Response,
  cors: Record<string, string>,
): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(cors)) headers.set(k, v);
  return new Response(res.body, { status: res.status, headers });
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Edge runtime missing required env: ${name}`);
  return value;
}

/// Build a Supabase client bound to the caller's JWT so PostgREST applies
/// RLS as that user. Returns the resolved user too. Throws on a missing or
/// invalid token; callers convert that into a 401.
export async function getAuthUser(
  req: Request,
): Promise<{ userId: string; supabase: SupabaseClient }> {
  const authHeader = req.headers.get("authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    throw new UnauthorizedError("Sign in required.");
  }

  const supabase = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    },
  );

  const { data, error } = await supabase.auth.getUser();
  if (error || !data?.user) {
    throw new UnauthorizedError("Invalid session.");
  }
  return { userId: data.user.id, supabase };
}

/// service_role client. Reserved for privileged paths (delete-account).
export function getAdminClient(): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false } },
  );
}

export class UnauthorizedError extends Error {}
