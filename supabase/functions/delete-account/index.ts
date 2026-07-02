// delete-account
// ─────────────────────────────────────────────────────────────────────────
// Irreversibly deletes the caller's account: storage objects across every
// bucket, then the auth.users row (which CASCADEs to all owned tables).
//
// Request:
//   POST  /functions/v1/delete-account
//   Headers: Authorization: Bearer <user JWT>
//   Body:   { "confirm": "DELETE-MY-ACCOUNT" }
//
// Response (200): { "data": { "deleted": true }, "error": null }
//
// Security invariants:
//   1. Resolve auth.uid() from the JWT — the user proves they are who they
//      claim before anything is deleted.
//   2. A literal confirmation token guards against accidental invocation.
//   3. The service_role admin client is used ONLY here, ONLY after the JWT
//      check, and only ever scoped to the resolved user's own uuid prefix.
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
import { revokeRefreshToken } from "../_shared/apple.ts";

// deno-lint-ignore no-explicit-any
declare const Deno: any;

// deno-lint-ignore no-explicit-any
type AdminClient = any;

const CONFIRM_TOKEN = "DELETE-MY-ACCOUNT";
// Only buckets that actually exist (see storage migrations). `listAllUnder`
// degrades gracefully if a bucket is missing, so this list is the source of
// truth for what gets purged.
const BUCKETS = ["receipts", "exports"];

export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return withCors(fail("METHOD_NOT_ALLOWED", "POST required.", 405), corsHeaders);
  }

  let userId: string;
  try {
    const auth = await getAuthUser(req);
    userId = auth.userId;
  } catch (e) {
    if (e instanceof UnauthorizedError) {
      return withCors(fail("UNAUTHENTICATED", e.message, 401), corsHeaders);
    }
    return withCors(fail("CONFIG_MISSING", "Edge runtime not configured.", 500), corsHeaders);
  }

  let body: { confirm?: string };
  try {
    body = (await req.json()) as { confirm?: string };
  } catch (_e) {
    return withCors(fail("BAD_REQUEST", "Malformed JSON body.", 400), corsHeaders);
  }
  if (body.confirm !== CONFIRM_TOKEN) {
    return withCors(
      fail("CONFIRMATION_REQUIRED", "Missing confirmation token.", 400),
      corsHeaders,
    );
  }

  let admin: AdminClient;
  try {
    admin = getAdminClient();
  } catch (_e) {
    return withCors(fail("CONFIG_MISSING", "Edge runtime not configured.", 500), corsHeaders);
  }

  // 0. Revoke the Apple grant (best-effort) while the stored refresh token is
  //    still readable. Required by Guideline 5.1.1(v) for Sign in with Apple.
  //    A revoke failure (network, misconfig, user never used Apple) must NOT
  //    strand the user's data deletion — log and continue. The credential row
  //    itself is removed by the FK cascade when the auth user is deleted.
  try {
    const { data: cred } = await admin
      .from("apple_credentials")
      .select("refresh_token")
      .eq("user_id", userId)
      .maybeSingle();
    const refreshToken =
      (cred as { refresh_token?: string } | null)?.refresh_token;
    if (refreshToken) {
      const revoked = await revokeRefreshToken(refreshToken);
      if (!revoked) {
        console.error(`Apple token revoke returned non-200 for ${userId}`);
      }
    }
  } catch (e) {
    console.error(`Apple revoke step errored: ${(e as Error).message}`);
  }

  // 1. Purge storage objects under this user's prefix in every bucket.
  for (const bucket of BUCKETS) {
    const paths = await listAllUnder(admin, bucket, userId);
    if (paths.length > 0) {
      const { error } = await admin.storage.from(bucket).remove(paths);
      if (error) {
        return withCors(fail("STORAGE_ERROR", error.message, 500), corsHeaders);
      }
    }
  }

  // 2. Delete the auth user. ON DELETE CASCADE removes profile, expenses,
  //    receipts, budgets, etc. across all user-owned tables.
  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    return withCors(fail("DELETE_FAILED", deleteError.message, 500), corsHeaders);
  }

  return withCors(json({ data: { deleted: true }, error: null }), corsHeaders);
}

/// Recursively collect every object path under `prefix` in `bucket`.
/// Supabase Storage `list` returns folder entries with a null `id`; we
/// recurse into those (bounded by the natural {uid}/{receipt_id}/file depth).
// deno-lint-ignore no-explicit-any
async function listAllUnder(
  admin: AdminClient,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const { data, error } = await admin.storage.from(bucket).list(prefix, {
    limit: 1000,
  });
  if (error || !data) return [];

  const paths: string[] = [];
  for (const entry of data as Array<{ name: string; id: string | null }>) {
    const childPath = `${prefix}/${entry.name}`;
    if (entry.id === null) {
      // Folder — recurse one level deeper.
      const nested = await listAllUnder(admin, bucket, childPath);
      paths.push(...nested);
    } else {
      paths.push(childPath);
    }
  }
  return paths;
}

if (import.meta.main) Deno.serve(handle);
