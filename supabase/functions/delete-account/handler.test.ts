// deno test --allow-env supabase/functions
import { assertEquals } from "jsr:@std/assert@1.0.14";
import { type Call, json, post, setEnv, stubFetch } from "../_test/stub.ts";

setEnv({ SUPABASE_URL: "https://sb.test", SUPABASE_ANON_KEY: "anon-key", SUPABASE_SERVICE_ROLE_KEY: "service-key" });
const { handler } = await import("./handler.ts");

function world(hasReports: boolean) {
  return stubFetch([
    (c: Call) => c.url.pathname === "/auth/v1/user"
      ? (c.headers.get("Authorization") === "Bearer res-token" ? json({ id: "u1" }) : json({}, 401)) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/rpc/request_account_deletion" ? json(!hasReports) : undefined,
    (c: Call) => c.url.pathname === "/auth/v1/admin/users/u1" ? json({}) : undefined,
  ]);
}

Deno.test("an account with no complaints is deleted outright, as its owner", async () => {
  const s = world(false);
  try {
    const res = await handler(post({}, { Authorization: "Bearer res-token" }));
    assertEquals(await res.json(), { ok: true, hard_deleted: true });
    const rpc = s.calls.find((c) => c.url.pathname.endsWith("request_account_deletion"))!;
    assertEquals(rpc.headers.get("Authorization"), "Bearer res-token");
    assertEquals(s.calls.find((c) => c.url.pathname === "/auth/v1/admin/users/u1")!.method, "DELETE");
  } finally { s.restore(); }
});

Deno.test("an account with complaints is scrubbed and its sign-in banned", async () => {
  const s = world(true);
  try {
    const res = await handler(post({}, { Authorization: "Bearer res-token" }));
    assertEquals((await res.json()).hard_deleted, false);
    const ban = s.calls.find((c) => c.url.pathname === "/auth/v1/admin/users/u1")!;
    assertEquals(ban.method, "PUT");
    assertEquals(JSON.parse(ban.body).ban_duration, "876000h");
  } finally { s.restore(); }
});

Deno.test("signed out, nothing is deleted", async () => {
  const s = world(false);
  try {
    assertEquals((await handler(post({}))).status, 401);
    assertEquals((await handler(post({}, { Authorization: "Bearer someone-else" }))).status, 400);
    assertEquals(s.calls.filter((c) => c.url.pathname.startsWith("/auth/v1/admin")).length, 0);
  } finally { s.restore(); }
});
