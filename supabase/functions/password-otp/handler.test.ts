// deno test --allow-env supabase/functions
import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1.0.14";
import { type Call, json, post, setEnv, stubFetch } from "../_test/stub.ts";

setEnv({ SUPABASE_URL: "https://sb.test", SUPABASE_SERVICE_ROLE_KEY: "service-key", SEMAPHORE_API_KEY: "sms-key" });
const { handler } = await import("./handler.ts");

/** One resident, +639171234567, and the database's answer to a guess. */
function supabase(outcome: "ok" | "wrong" | "expired", left = 4) {
  return stubFetch([
    (c: Call) => c.url.pathname === "/rest/v1/users" && c.method === "GET"
      ? json(c.url.searchParams.get("mobile_number") === "eq.+639171234567" ? [{ id: "u1", is_suspended: false, is_retired: false }] : [])
      : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/rpc/otp_attempt"
      ? json([{ outcome, attempts_left: left, otp_id: "o1", new_mobile: null }]) : undefined,
    (c: Call) => c.url.pathname === "/auth/v1/admin/users/u1" ? json({ id: "u1" }) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/password_otps" && c.method === "POST" ? json([{ id: "o1" }]) : undefined,
    (c: Call) => c.url.pathname.startsWith("/rest/v1/") ? json([]) : undefined,
    (c: Call) => c.url.hostname === "api.semaphore.co" ? json([{ message_id: 1 }]) : undefined,
  ]);
}

Deno.test("a wrong code says how many tries are left; the count is the database's", async () => {
  const s = supabase("wrong", 3);
  try {
    const res = await handler(post({ action: "verify", mobile: "09171234567", code: "123456", password: "new-password" }));
    assertEquals(res.status, 400);
    assertMatch((await res.json()).message, /3 tries left/);
    const guess = s.calls.find((c) => c.url.pathname === "/rest/v1/rpc/otp_attempt")!;
    assertEquals(JSON.parse(guess.body).p_purpose, "password");
    assert(!s.calls.some((c) => c.url.pathname.startsWith("/auth/v1/admin")), "password must not change");
  } finally { s.restore(); }
});

Deno.test("the right code changes the password and signs the account out everywhere", async () => {
  const s = supabase("ok");
  try {
    const res = await handler(post({ action: "verify", mobile: "09171234567", code: "123456", password: "new-password" }));
    assertEquals(res.status, 200);
    const paths = s.calls.map((c) => `${c.method} ${c.url.pathname}`);
    assert(paths.includes("PUT /auth/v1/admin/users/u1"));
    assert(paths.includes("POST /rest/v1/rpc/revoke_user_sessions"));
  } finally { s.restore(); }
});

Deno.test("an expired code is just 'wrong or expired'", async () => {
  const s = supabase("expired");
  try {
    const res = await handler(post({ action: "verify", mobile: "09171234567", code: "123456", password: "new-password" }));
    assertMatch((await res.json()).message, /wrong or has expired/);
  } finally { s.restore(); }
});

Deno.test("asking for a code answers the same whether or not the number has an account", async () => {
  const s = supabase("ok");
  try {
    const none = await (await handler(post({ action: "send", mobile: "09179999999" }))).json();
    assert(!s.calls.some((c) => c.url.hostname === "api.semaphore.co"), "no text for a number with no account");
    s.calls.length = 0;
    const some = await (await handler(post({ action: "send", mobile: "09171234567" }))).json();
    assert(s.calls.some((c) => c.url.hostname === "api.semaphore.co"));
    assertEquals(none.message, some.message);
  } finally { s.restore(); }
});

Deno.test("bad input is refused before anything is looked up", async () => {
  const s = supabase("ok");
  try {
    assertEquals((await handler(post({ action: "send", mobile: "12345" }))).status, 400);
    assertEquals((await handler(post({ action: "verify", mobile: "09171234567", code: "12", password: "x" }))).status, 400);
    assertEquals(s.calls.length, 0);
  } finally { s.restore(); }
});
