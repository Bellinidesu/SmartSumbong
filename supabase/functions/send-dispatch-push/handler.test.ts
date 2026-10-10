// deno test --allow-env supabase/functions
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { type Call, json, post, setEnv, stubFetch } from "../_test/stub.ts";

// A throwaway service-account key, so the real JWT signing runs.
const pair = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true, ["sign", "verify"]);
const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;

setEnv({
  SUPABASE_URL: "https://sb.test", SUPABASE_SERVICE_ROLE_KEY: "service-key",
  FCM_PROJECT_ID: "proj", FCM_CLIENT_EMAIL: "push@proj.iam.gserviceaccount.com", FCM_PRIVATE_KEY: pem,
  PUSH_WEBHOOK_SECRET: "hook-secret",
});
const { handler } = await import("./handler.ts");

const NOTE = { id: "0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11", user_id: "u1", report_id: "r1", kind: "status_change", message: "Your complaint is in progress." };
const hook = (record: unknown = NOTE, secret = "hook-secret") =>
  post({ type: "INSERT", table: "notifications", record }, { "x-webhook-secret": secret });

function world(opts: { muted?: string[]; tokens?: string[]; stored?: boolean } = {}) {
  return stubFetch([
    (c: Call) => c.url.pathname === "/rest/v1/notifications" ? json(opts.stored === false ? [] : [NOTE]) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/users" ? json([{ muted_notification_kinds: opts.muted ?? [] }]) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/device_tokens" && c.method === "GET"
      ? json((opts.tokens ?? []).map((t) => ({ fcm_token: t }))) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/device_tokens" && c.method === "DELETE" ? json(null) : undefined,
    (c: Call) => c.url.hostname === "oauth2.googleapis.com" ? json({ access_token: "google-token" }) : undefined,
    (c: Call) => c.url.hostname === "fcm.googleapis.com"
      ? (JSON.parse(c.body).message.token === "gone" ? json({ error: { status: "NOT_FOUND", details: "UNREGISTERED" } }, 404) : json({ name: "ok" }))
      : undefined,
  ]);
}

Deno.test("without the webhook secret nothing happens", async () => {
  const s = world({ tokens: ["phone"] });
  try {
    assertEquals((await handler(hook(NOTE, "wrong"))).status, 403);
    assertEquals(s.calls.length, 0);
  } finally { s.restore(); }
});

Deno.test("only a stored notification is sent, never the payload's text", async () => {
  const s = world({ stored: false, tokens: ["phone"] });
  try {
    const res = await handler(hook({ ...NOTE, message: "forged" }));
    assertEquals(await res.text(), "no such notification");
    assert(!s.calls.some((c) => c.url.hostname === "fcm.googleapis.com"));
  } finally { s.restore(); }
});

Deno.test("a kind the recipient muted is not pushed", async () => {
  const s = world({ muted: ["status_change"], tokens: ["phone"] });
  try {
    assertEquals(await (await handler(hook())).text(), "muted by recipient");
  } finally { s.restore(); }
});

Deno.test("pushes to every phone, drops uninstalled ones, reuses the Google token", async () => {
  const s = world({ tokens: ["phone", "gone"] });
  try {
    assertEquals(await (await handler(hook())).text(), "sent");
    assertEquals(s.calls.filter((c) => c.url.hostname === "fcm.googleapis.com").length, 2);
    assert(s.calls.some((c) => c.url.pathname === "/rest/v1/device_tokens" && c.method === "DELETE" && c.url.search.includes("gone")));
    const sent = JSON.parse(s.calls.find((c) => c.url.hostname === "fcm.googleapis.com")!.body);
    assertEquals(sent.message.android.notification.tag, "r1");
    s.calls.length = 0;
    await handler(hook());
    assertEquals(s.calls.filter((c) => c.url.hostname === "oauth2.googleapis.com").length, 0, "token cached");
  } finally { s.restore(); }
});
