// Shared "Sign in with Apple" server helpers: build the ES256 client secret,
// exchange a native authorizationCode for a refresh token, and revoke a token.
//
// Apple requires the client_secret to be an ES256 JWT signed with the private
// key (.p8) downloaded from the Apple Developer portal. That key never ships to
// the client — it lives only as Edge Function secrets:
//
//   APPLE_PRIVATE_KEY_B64  base64 of the AuthKey_XXXXXXXXXX.p8 file contents
//   APPLE_TEAM_ID          10-char Apple Team ID
//   APPLE_KEY_ID           10-char Key ID of the .p8 key
//   APPLE_CLIENT_ID        the audience — for native iOS this is the bundle id
//                          (site.tunckankilic.smartspend)
//
// Refs:
//   developer.apple.com/documentation/sign_in_with_apple/generate_and_validate_tokens
//   developer.apple.com/documentation/sign_in_with_apple/revoke_tokens

import { requireEnv } from "./runtime.ts";

const APPLE_AUTH_HOST = "https://appleid.apple.com";

function base64UrlFromBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlFromString(value: string): string {
  return base64UrlFromBytes(new TextEncoder().encode(value));
}

/// Decode the base64-encoded .p8 (PKCS#8 PEM) into an ES256 signing key.
async function importPrivateKey(): Promise<CryptoKey> {
  const pem = atob(requireEnv("APPLE_PRIVATE_KEY_B64"));
  const der = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(der), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    raw,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/// Build the short-lived ES256 client_secret JWT Apple requires.
export async function makeClientSecret(): Promise<string> {
  const teamId = requireEnv("APPLE_TEAM_ID");
  const keyId = requireEnv("APPLE_KEY_ID");
  const clientId = requireEnv("APPLE_CLIENT_ID");

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = {
    iss: teamId,
    iat: now,
    exp: now + 300, // 5 min — one request, no need to live longer.
    aud: APPLE_AUTH_HOST,
    sub: clientId,
  };
  const signingInput = `${base64UrlFromString(JSON.stringify(header))}.` +
    `${base64UrlFromString(JSON.stringify(payload))}`;

  const key = await importPrivateKey();
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  // Web Crypto returns the raw r||s pair that ES256/JOSE expects.
  return `${signingInput}.${base64UrlFromBytes(new Uint8Array(signature))}`;
}

/// Exchange a native authorizationCode for Apple tokens. Returns the
/// refresh_token, or null when Apple omits it (caller decides how to handle).
export async function exchangeAuthCode(code: string): Promise<string | null> {
  const clientSecret = await makeClientSecret();
  const res = await fetch(`${APPLE_AUTH_HOST}/auth/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: requireEnv("APPLE_CLIENT_ID"),
      client_secret: clientSecret,
      grant_type: "authorization_code",
      code,
    }).toString(),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Apple token exchange failed (${res.status}): ${detail}`);
  }
  const data = (await res.json()) as { refresh_token?: string };
  return data.refresh_token ?? null;
}

/// Revoke an Apple refresh token. Best-effort: true on 200, false otherwise so
/// the caller can log without stranding the user's account deletion.
export async function revokeRefreshToken(
  refreshToken: string,
): Promise<boolean> {
  const clientSecret = await makeClientSecret();
  const res = await fetch(`${APPLE_AUTH_HOST}/auth/revoke`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: requireEnv("APPLE_CLIENT_ID"),
      client_secret: clientSecret,
      token: refreshToken,
      token_type_hint: "refresh_token",
    }).toString(),
  });
  return res.ok;
}
