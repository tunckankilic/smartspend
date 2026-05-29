// Deno tests for export-csv. Run with:
//   deno test --allow-net --allow-env supabase/functions/__tests__/

import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildCsv, handle } from "../export-csv/index.ts";

Deno.test("non-GET is rejected with 405", async () => {
  const res = await handle(
    new Request("http://x/export-csv", { method: "POST" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("missing Authorization header is rejected with 401", async () => {
  const res = await handle(
    new Request("http://x/export-csv", { method: "GET" }),
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error.code, "UNAUTHENTICATED");
});

Deno.test("buildCsv writes a header and one row per expense", () => {
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: 1250,
      currency: "TRY",
      note: "lunch",
      category: { name: "Restoran" },
      receipt: { store_name: "Kebapçı" },
    },
  ]);
  const lines = csv.split("\n");
  assertEquals(lines[0], "date,store,category,amount,currency,note");
  assertStringIncludes(lines[1], "2026-05-01,Kebapçı,Restoran,1250,TRY,lunch");
});

Deno.test("buildCsv quotes cells containing commas or quotes", () => {
  const csv = buildCsv([
    {
      date: "2026-05-01",
      amount: 100,
      currency: "TRY",
      note: 'has, comma and "quote"',
      category: null,
      receipt: null,
    },
  ]);
  assertStringIncludes(csv, '"has, comma and ""quote"""');
});
