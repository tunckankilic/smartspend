// Deno tests for delete-account. Run with:
//   deno test --allow-net --allow-env supabase/functions/__tests__/

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handle } from "../delete-account/index.ts";

Deno.test("non-POST is rejected with 405", async () => {
  const res = await handle(
    new Request("http://x/delete-account", { method: "GET" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("missing Authorization header is rejected with 401", async () => {
  const res = await handle(
    new Request("http://x/delete-account", {
      method: "POST",
      body: JSON.stringify({ confirm: "DELETE-MY-ACCOUNT" }),
    }),
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error.code, "UNAUTHENTICATED");
});
