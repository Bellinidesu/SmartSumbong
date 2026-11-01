// deno test --allow-env supabase/functions
import { assertEquals } from "jsr:@std/assert@1.0.19";
import { type Call, json, post, setEnv, stubFetch } from "../_test/stub.ts";

setEnv({ SUPABASE_URL: "https://sb.test", SUPABASE_ANON_KEY: "anon-key", SUPABASE_SERVICE_ROLE_KEY: "service-key" });
const { handler } = await import("./handler.ts");

type World = { dev?: boolean; test?: boolean; linked?: boolean; acctTest?: boolean };

function world(w: World = {}) {
  const { dev = true, test = false, linked = true, acctTest = true } = w;
  return stubFetch([
    (c: Call) => c.url.pathname === "/auth/v1/user"
      ? (c.headers.get("Authorization") === "Bearer dev-token" ? json({ id: "d1" }) : json({}, 401)) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/users" && c.url.search.includes("id=eq.d1")
      ? json([{ is_dev: dev, is_test: test, is_suspended: false }]) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/dev_test_accounts"
      ? json(linked ? [{ account: "t1" }] : []) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/users" && c.url.search.includes("id=eq.t1")
      ? json([{ email: "dev-x-committee@test.smartsumbong.ph", is_test: acctTest, role: "admin", is_suspended: false }]) : undefined,
    (c: Call) => c.url.pathname === "/auth/v1/admin/generate_link" ? json({ hashed_token: "h123" }) : undefined,
    (c: Call) => c.url.pathname === "/auth/v1/verify"
      ? json({ access_token: "t1-access", refresh_token: "t1-refresh", expires_in: 3600, user: { id: "t1" } }) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/dev_level_switches" ? new Response(null, { status: 201 }) : undefined,
  ]);
}

Deno.test("a developer gets a session for their own test Kagawad, and the switch is recorded", async () => {
  const s = world();
  try {
    const res = await handler(post({ level: "committee" }, { Authorization: "Bearer dev-token" }));
    assertEquals(res.status, 200);
    assertEquals((await res.json()).access_token, "t1-access");
    const gen = s.calls.find((c) => c.url.pathname === "/auth/v1/admin/generate_link")!;
    assertEquals(gen.headers.get("Authorization"), "Bearer service-key");
    assertEquals(JSON.parse(gen.body), { type: "magiclink", email: "dev-x-committee@test.smartsumbong.ph" });
    const ver = s.calls.find((c) => c.url.pathname === "/auth/v1/verify")!;
    assertEquals(ver.headers.get("Authorization"), null);   // verify is the anon key's, never the service role's
    assertEquals(JSON.parse(ver.body).token_hash, "h123");
    assertEquals(JSON.parse(s.calls.find((c) => c.url.pathname === "/rest/v1/dev_level_switches")!.body), { owner: "d1", level: "committee" });
  } finally { s.restore(); }
});

Deno.test("someone who is not a developer gets nothing", async () => {
  const s = world({ dev: false });
  try {
    const res = await handler(post({ level: "super" }, { Authorization: "Bearer dev-token" }));
    assertEquals(res.status, 403);
    assertEquals(s.calls.some((c) => c.url.pathname === "/auth/v1/admin/generate_link"), false);
  } finally { s.restore(); }
});

Deno.test("a test account cannot switch onward", async () => {
  const s = world({ test: true });
  try {
    assertEquals((await handler(post({ level: "super" }, { Authorization: "Bearer dev-token" }))).status, 403);
  } finally { s.restore(); }
});

Deno.test("a rung with no linked test account, or one not marked test, is refused", async () => {
  let s = world({ linked: false });
  try {
    assertEquals((await handler(post({ level: "captain" }, { Authorization: "Bearer dev-token" }))).status, 404);
  } finally { s.restore(); }
  s = world({ acctTest: false });
  try {
    assertEquals((await handler(post({ level: "captain" }, { Authorization: "Bearer dev-token" }))).status, 409);
    assertEquals(s.calls.some((c) => c.url.pathname === "/auth/v1/admin/generate_link"), false);
  } finally { s.restore(); }
});

Deno.test("signed out, or an unknown rung, or not a POST: nothing happens", async () => {
  const s = world();
  try {
    assertEquals((await handler(post({ level: "super" }))).status, 401);
    assertEquals((await handler(post({ level: "god" }, { Authorization: "Bearer dev-token" }))).status, 400);
    assertEquals((await handler(new Request("http://localhost/", { method: "GET" }))).status, 405);
    assertEquals(s.calls.some((c) => c.url.pathname === "/auth/v1/admin/generate_link"), false);
  } finally { s.restore(); }
});
