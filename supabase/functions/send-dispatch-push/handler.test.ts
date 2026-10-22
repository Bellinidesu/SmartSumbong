// deno test --allow-env supabase/functions
import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { type Call, json, post, setEnv, stubFetch } from "../_test/stub.ts";
import { b64u } from "./webpush.ts";

// A throwaway service-account key, so the real JWT signing runs.
const pair = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true, ["sign", "verify"]);
const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;

// Throwaway VAPID keys, and a browser's own key pair, so the real encryption runs.
const raw = async (k: CryptoKey) => b64u(new Uint8Array(await crypto.subtle.exportKey("raw", k)));
const vapidPair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const browserPair = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
const BROWSER = { id: 7, endpoint: "https://fcm.googleapis.com/fcm/send/abc", p256dh: await raw(browserPair.publicKey), auth: "BTBZMqHH6r4Tts7J_aSIgg" };

setEnv({
  SUPABASE_URL: "https://sb.test", SUPABASE_SERVICE_ROLE_KEY: "service-key",
  FCM_PROJECT_ID: "proj", FCM_CLIENT_EMAIL: "push@proj.iam.gserviceaccount.com", FCM_PRIVATE_KEY: pem,
  PUSH_WEBHOOK_SECRET: "hook-secret",
  VAPID_PUBLIC_KEY: await raw(vapidPair.publicKey), VAPID_PRIVATE_KEY: (await crypto.subtle.exportKey("jwk", vapidPair.privateKey)).d!,
  VAPID_SUBJECT: "mailto:test@example.org",
});
const { handler } = await import("./handler.ts");

const NOTE = { id: "0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11", user_id: "u1", report_id: "r1", kind: "status_change", message: "Your complaint is in progress." };
const hook = (record: unknown = NOTE, secret = "hook-secret") =>
  post({ type: "INSERT", table: "notifications", record }, { "x-webhook-secret": secret });

type Web = typeof BROWSER;
function world(opts: { why?: string; tokens?: string[]; web?: Web[]; stored?: boolean; kind?: string } = {}) {
  return stubFetch([
    // One request: push_plan (0136) answers whether to send, and where to.
    (c: Call) => c.url.pathname === "/rest/v1/rpc/push_plan"
      ? json(opts.stored === false ? null : {
        send: !opts.why, why: opts.why ?? null, record: { ...NOTE, kind: opts.kind ?? NOTE.kind }, urgent: false,
        tokens: opts.tokens ?? [], web: opts.web ?? [],
      })
      : undefined,
    (c: Call) => ["/rest/v1/device_tokens", "/rest/v1/web_push_subscriptions", "/rest/v1/notifications"].includes(c.url.pathname) &&
        ["DELETE", "PATCH"].includes(c.method) ? new Response(null, { status: 204 }) : undefined,
    (c: Call) => c.url.hostname === "oauth2.googleapis.com" ? json({ access_token: "google-token" }) : undefined,
    (c: Call) => c.url.hostname === "fcm.googleapis.com" && c.url.pathname.startsWith("/fcm/send/")
      ? new Response(null, { status: c.url.pathname.endsWith("/gone") ? 410 : 201 })
      : undefined,
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
  const s = world({ why: "muted", tokens: ["phone"] });
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

Deno.test("one database request per push: the plan for that notification", async () => {
  const s = world({ tokens: ["phone"] });
  try {
    await handler(hook());
    const db = s.calls.filter((c) => c.url.hostname === "sb.test");
    assertEquals(db.length, 1);
    assertEquals(JSON.parse(db[0].body), { p_id: NOTE.id });
  } finally { s.restore(); }
});

Deno.test("the recipient's quiet hours or case choice hold the push back", async () => {
  const s = world({ why: "quiet hours", tokens: ["phone"], web: [BROWSER] });
  try {
    assertEquals(await (await handler(hook())).text(), "held: quiet hours");
    assert(!s.calls.some((c) => c.url.hostname === "fcm.googleapis.com"));
  } finally { s.restore(); }
});

Deno.test("browsers get an encrypted push signed with our VAPID key; a forgotten one is removed", async () => {
  const s = world({ web: [BROWSER, { ...BROWSER, id: 8, endpoint: "https://fcm.googleapis.com/fcm/send/gone" }] });
  try {
    assertEquals(await (await handler(hook())).text(), "sent");
    const push = s.calls.find((c) => c.url.pathname === "/fcm/send/abc")!;
    assertEquals(push.headers.get("content-encoding"), "aes128gcm");
    assert(push.headers.get("authorization")!.startsWith("vapid t="));
    assertEquals(push.headers.get("topic"), "r1");
    assert(!push.body.includes("in progress"), "the text travels encrypted");
    assert(s.calls.some((c) => c.url.pathname === "/rest/v1/web_push_subscriptions" && c.method === "PATCH" && c.url.search.includes("eq.7")));
    assert(s.calls.some((c) => c.url.pathname === "/rest/v1/web_push_subscriptions" && c.method === "DELETE" && c.url.search.includes("eq.8")));
    assert(!s.calls.some((c) => c.url.hostname === "oauth2.googleapis.com"), "no phones, no Google token");
  } finally { s.restore(); }
});

Deno.test("a test alert is sent, then removed from the inbox", async () => {
  const s = world({ kind: "test", web: [BROWSER] });
  try {
    assertEquals(await (await handler(hook())).text(), "sent");
    assert(s.calls.some((c) => c.url.pathname === "/rest/v1/notifications" && c.method === "DELETE" && c.url.search.includes("kind=eq.test")));
  } finally { s.restore(); }
});

Deno.test("a status check with no body is answered, not logged as an error", async () => {
  const s = world({ tokens: ["phone"] });
  try {
    const h = { "x-webhook-secret": "hook-secret" };
    assertEquals((await handler(new Request("https://fn.test/", { method: "OPTIONS", headers: h }))).status, 200);
    assertEquals((await handler(new Request("https://fn.test/", { method: "POST", headers: h }))).status, 200);
    assertEquals(s.calls.length, 0);
  } finally { s.restore(); }
});
