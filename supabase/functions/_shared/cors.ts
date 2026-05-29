// Shared CORS headers for all Edge Functions.
//
// The Flutter client calls these via `supabase.functions.invoke`, which
// attaches the user JWT automatically. The wildcard origin is safe because
// every function still validates the JWT before doing any work — CORS is not
// the auth boundary here, RLS + JWT verification is.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
