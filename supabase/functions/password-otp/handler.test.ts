// deno test --allow-env supabase/functions
import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1.0.19";
import { type Call, json, post, setEnv, stubFetch } from "../_test/stub.ts";

setEnv({ SUPABASE_URL: "https://sb.test", SUPABASE_SERVICE_ROLE_KEY: "service-key", SEMAPHORE_API_KEY: "sms-key" });
const { handler, sixDigits, useSmtpConnection } = await import("./handler.ts");
const { message } = await import("./smtp.ts");

/** The hourly allowances (take_rate_slot, 0116): every slot is free unless a test says otherwise. */
let slotAnswer = true;
const slots = (c: Call) => c.url.pathname === "/rest/v1/rpc/take_rate_slot" ? json(slotAnswer) : undefined;

/** One resident, +639171234567, and the database's answer to a guess. */
function supabase(outcome: "ok" | "wrong" | "expired", left = 4) {
  return stubFetch([slots,
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

Deno.test("the code goes by Semaphore's OTP route, as our own code in the {otp} place", async () => {
  const s = supabase("ok");
  try {
    await handler(post({ action: "send", mobile: "09171234567" }));
    const sms = s.calls.find((c) => c.url.hostname === "api.semaphore.co")!;
    assertEquals(sms.url.pathname, "/api/v4/otp");
    const form = new URLSearchParams(sms.body);
    assertEquals(form.get("number"), "09171234567");
    assertMatch(form.get("code") ?? "", /^\d{6}$/);
    assertMatch(form.get("message") ?? "", /\{otp\}/);
    assert(!(form.get("message") ?? "").includes(form.get("code")!), "the code is Semaphore's to place, not written in");
    assert(!form.has("sendername"), "no sender name unless one is set");
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

Deno.test("codes are six digits", () => {
  for (let i = 0; i < 1000; i++) assertMatch(sixDigits(), /^\d{6}$/);
});

// ---------- by email (0174) ----------

/** A pretend Gmail: answers each command and keeps what was said, so a test reads the message without any network. */
function fakeGmail(opts: { refuseAuth?: boolean } = {}) {
  const said: string[] = [];
  let data = "";
  let inData = false;
  let pending = "";
  let out = "220 smtp.gmail.com ESMTP ready\r\n";
  let wake: (() => void) | null = null;
  const reply = (s: string) => { out += s; wake?.(); };
  const opened: { hostname: string; port: number }[] = [];
  const conn = {
    async read(p: Uint8Array): Promise<number | null> {
      while (!out) await new Promise<void>((r) => (wake = r));
      const b = new TextEncoder().encode(out);
      const n = Math.min(b.length, p.length);
      p.set(b.subarray(0, n));
      out = new TextDecoder().decode(b.subarray(n));
      return n;
    },
    write(p: Uint8Array): Promise<number> {
      pending += new TextDecoder().decode(p);
      for (;;) {
        if (inData) {
          const end = pending.indexOf("\r\n.\r\n");
          if (end < 0) break;
          data = pending.slice(0, end);
          pending = pending.slice(end + 5);
          inData = false;
          reply("250 2.0.0 OK queued\r\n");
          continue;
        }
        const nl = pending.indexOf("\r\n");
        if (nl < 0) break;
        const line = pending.slice(0, nl);
        pending = pending.slice(nl + 2);
        said.push(line);
        if (line.startsWith("EHLO")) reply("250-smtp.gmail.com at your service\r\n250-SIZE 35882577\r\n250 AUTH LOGIN PLAIN\r\n");
        else if (line.startsWith("AUTH")) reply(opts.refuseAuth ? "535 5.7.8 Username and Password not accepted\r\n" : "235 2.7.0 Accepted\r\n");
        else if (line.startsWith("MAIL") || line.startsWith("RCPT")) reply("250 2.1.0 OK\r\n");
        else if (line === "DATA") { inData = true; reply("354 Go ahead\r\n"); }
        else if (line === "QUIT") reply("221 2.0.0 closing connection\r\n");
        else reply("502 5.5.1 Unrecognized command\r\n");
      }
      return Promise.resolve(p.length);
    },
    close() {},
  };
  useSmtpConnection((o) => { opened.push(o); return Promise.resolve(conn); });
  /** The decoded plain-text and HTML parts of the message. */
  const parts = () => {
    const bodies = [...data.matchAll(/Content-Transfer-Encoding: base64\r\n\r\n([A-Za-z0-9+/=\r\n]+?)\r\n--/g)]
      .map((m) => new TextDecoder().decode(Uint8Array.from(atob(m[1].replace(/\r\n/g, "")), (c) => c.charCodeAt(0))));
    return { text: bodies[0] ?? "", html: bodies[1] ?? "" };
  };
  return { said, opened, data: () => data, parts };
}

const MAIL_ENV = { SMTP_USER: "barangay183.test@gmail.com", SMTP_PASS: "abcd efgh ijkl mnop" };
function withMail(on: boolean, sms = true) {
  if (on) setEnv(MAIL_ENV); else for (const k of Object.keys(MAIL_ENV)) Deno.env.delete(k);
  if (sms) setEnv({ SEMAPHORE_API_KEY: "sms-key" }); else Deno.env.delete("SEMAPHORE_API_KEY");
}

/** The resident +639171234567 with an email, confirmed or not; and, signed in, the same person. */
function mailbase(opts: { confirmed: boolean; email?: string | null; outcome?: "ok" | "wrong" | "expired"; pending?: string | null; updated?: boolean }) {
  const email = opts.email === undefined ? "ana.cruz@gmail.com" : opts.email;
  const row = { id: "u1", role: "resident", mobile_number: "+639171234567", email, email_confirmed_at: opts.confirmed ? "2026-11-17T00:00:00Z" : null, is_suspended: false, is_retired: false };
  return stubFetch([slots,
    (c: Call) => c.url.pathname === "/auth/v1/user" ? json({ id: "u1" }) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/users" && c.method === "GET"
      ? json(c.url.searchParams.get("mobile_number") === "eq.+639171234567" || c.url.searchParams.get("id") === "eq.u1" ? [row] : [])
      : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/users" && c.method === "PATCH" ? json(opts.updated === false ? [] : [row]) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/rpc/otp_attempt"
      ? json([{ outcome: opts.outcome ?? "ok", attempts_left: 4, otp_id: "o9", new_mobile: null }]) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/password_otps" && c.method === "POST" ? json([{ id: "o9" }]) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/password_otps" && c.method === "GET" && c.url.searchParams.get("select") === "new_email"
      ? json(opts.pending === null ? [] : [{ new_email: opts.pending ?? email }]) : undefined,
    (c: Call) => c.url.pathname.startsWith("/rest/v1/") ? json([]) : undefined,
    (c: Call) => c.url.hostname === "api.semaphore.co" ? json([{ message_id: 1 }]) : undefined,
  ]);
}
const signedIn = { Authorization: "Bearer user-token" };

Deno.test("a confirmed email gets the reset code from Gmail, and the answer names it masked", async () => {
  withMail(true);
  const s = mailbase({ confirmed: true });
  const g = fakeGmail();
  try {
    const r = await (await handler(post({ action: "send", mobile: "09171234567" }))).json();
    assertEquals(r.ok, true);
    assertEquals(r.channel, "email");
    assertEquals(r.to, "a•••@gmail.com");
    assertMatch(r.message, /We sent a code to the email on your account: a•••@gmail\.com/);
    assert(!s.calls.some((c) => c.url.hostname === "api.semaphore.co"), "no text when the email went");
    assertEquals(g.opened, [{ hostname: "smtp.gmail.com", port: 465 }]);
    const auth = g.said.find((l) => l.startsWith("AUTH PLAIN "))!;
    assertEquals(atob(auth.slice(11)), "\0barangay183.test@gmail.com\0abcdefghijklmnop", "the app password's spaces are dropped");
    assertEquals(g.said.find((l) => l.startsWith("RCPT")), "RCPT TO:<ana.cruz@gmail.com>");
    assertMatch(g.data(), /^From: =\?UTF-8\?B\?[^?]+\?= <barangay183\.test@gmail\.com>/m);
    const { text, html } = g.parts();
    const code = text.match(/Your code: (\d{3}) (\d{3})/)!;
    assert(code, "the plain text carries the code");
    assertMatch(html, /email-header\.jpg/);
    assertMatch(html, new RegExp(`${code[1]} ${code[2]}`));
    assertMatch(text, /0917•••4567/);
    assert(!text.includes("+639171234567"), "the number is masked in the email");
    const stored = s.calls.find((c) => c.url.pathname === "/rest/v1/password_otps" && c.method === "POST")!;
    assertEquals(JSON.parse(stored.body).purpose, undefined, "a reset code keeps the password purpose (the column's default)");
  } finally { s.restore(); withMail(false); }
});

Deno.test("no confirmed email and no SMS: the same 'No email on this account' as a number with no account", async () => {
  withMail(true, false);
  const s = mailbase({ confirmed: false });
  const g = fakeGmail();
  try {
    const some = await (await handler(post({ action: "send", mobile: "09171234567" }))).json();
    const none = await (await handler(post({ action: "send", mobile: "09179999999" }))).json();
    assertEquals(some, none);
    assertEquals(some.code, "no_email");
    assertMatch(some.message, /No email on this account\. Add one in Edit Profile, or ask the barangay hall to reset it\./);
    assertEquals(g.opened.length, 0, "an unconfirmed address gets nothing");
    assert(!s.calls.some((c) => c.method === "POST" && c.url.pathname === "/rest/v1/password_otps"), "no code is stored");
  } finally { s.restore(); withMail(false); }
});

Deno.test("no confirmed email, SMS set up: the code goes by text as before", async () => {
  withMail(true, true);
  const s = mailbase({ confirmed: false });
  const g = fakeGmail();
  try {
    const r = await (await handler(post({ action: "send", mobile: "09171234567" }))).json();
    assertEquals(r.channel, "sms");
    assert(s.calls.some((c) => c.url.hostname === "api.semaphore.co"));
    assertEquals(g.opened.length, 0);
  } finally { s.restore(); withMail(false); }
});

Deno.test("Gmail refusing the sign-in: the code is taken back, the answer says try again, and the password is never logged", async () => {
  withMail(true, false);
  const s = mailbase({ confirmed: true });
  fakeGmail({ refuseAuth: true });
  try {
    const res = await handler(post({ action: "send", mobile: "09171234567" }));
    assertEquals(res.status, 502);
    assert(s.calls.some((c) => c.method === "DELETE" && c.url.pathname === "/rest/v1/password_otps"));
    const logged = s.calls.filter((c) => c.url.pathname === "/rest/v1/rpc/log_portal_error").map((c) => c.body).join(" ");
    assertMatch(logged, /sign-in refused/);
    assert(!logged.includes("abcd") && !logged.includes("abcdefghijklmnop"), "no secret in the error log");
  } finally { s.restore(); withMail(false); }
});

Deno.test("confirming an email: a code to the address on the profile, bound to that address", async () => {
  withMail(true, false);
  const s = mailbase({ confirmed: false });
  const g = fakeGmail();
  try {
    const r = await (await handler(post({ action: "email_send" }, signedIn))).json();
    assertEquals(r.ok, true);
    assertEquals(r.to, "a•••@gmail.com");
    const stored = JSON.parse(s.calls.find((c) => c.url.pathname === "/rest/v1/password_otps" && c.method === "POST")!.body);
    assertEquals(stored.purpose, "email");
    assertEquals(stored.new_email, "ana.cruz@gmail.com");
    assertEquals(g.said.find((l) => l.startsWith("RCPT")), "RCPT TO:<ana.cruz@gmail.com>");
    assertMatch(g.parts().text, /Confirm your email/);
  } finally { s.restore(); withMail(false); }
});

Deno.test("confirming: signed out is refused, an already confirmed email sends nothing, no email asks for one", async () => {
  withMail(true, false);
  try {
    let s = mailbase({ confirmed: true });
    let g = fakeGmail();
    assertEquals((await handler(post({ action: "email_send" }))).status, 401);
    const r = await (await handler(post({ action: "email_send" }, signedIn))).json();
    assertEquals(r.already, true);
    assertEquals(g.opened.length, 0);
    s.restore();
    s = mailbase({ confirmed: false, email: null });
    g = fakeGmail();
    assertEquals((await handler(post({ action: "email_send" }, signedIn))).status, 400);
    assertEquals(g.opened.length, 0);
    s.restore();
  } finally { withMail(false); }
});

Deno.test("the right code marks the email confirmed, only while it is still the same address", async () => {
  withMail(true, false);
  let s = mailbase({ confirmed: false });
  try {
    const ok = await handler(post({ action: "email_verify", code: "123456" }, signedIn));
    assertEquals(ok.status, 200);
    const guess = JSON.parse(s.calls.find((c) => c.url.pathname === "/rest/v1/rpc/otp_attempt")!.body);
    assertEquals(guess.p_purpose, "email");
    const mark = s.calls.find((c) => c.url.pathname === "/rest/v1/users" && c.method === "PATCH")!;
    assertEquals(mark.url.searchParams.get("email"), "eq.ana.cruz@gmail.com");
    assertEquals(Object.keys(JSON.parse(mark.body)), ["email_confirmed_at"]);
    assert(s.calls.some((c) => c.url.pathname === "/rest/v1/account_audit" && JSON.parse(c.body).action === "email_confirmed"));
    s.restore();

    // the code went to an address the person has since changed
    s = mailbase({ confirmed: false, pending: "old.address@gmail.com" });
    const moved = await handler(post({ action: "email_verify", code: "123456" }, signedIn));
    assertEquals(moved.status, 409);
    assert(!s.calls.some((c) => c.url.pathname === "/rest/v1/users" && c.method === "PATCH"), "nothing confirmed");
    s.restore();

    // a wrong code says how many tries are left
    s = mailbase({ confirmed: false, outcome: "wrong" });
    const wrong = await handler(post({ action: "email_verify", code: "123456" }, signedIn));
    assertMatch((await wrong.json()).message, /4 tries left/);
    assert(!s.calls.some((c) => c.url.pathname === "/rest/v1/users" && c.method === "PATCH"));
  } finally { s.restore(); withMail(false); }
});

Deno.test("the message: UTF-8 subject and name as RFC 2047 words, both parts base64, no bare line breaks in headers", () => {
  const m = message("a@gmail.com", "SmartSumbong · Barangay 183", { to: "b@gmail.com", subject: "Kumpirmahin ang email · 183", text: "Hi\nñ", html: "<b>ñ</b>" });
  assertMatch(m, /^From: =\?UTF-8\?B\?/m);
  assertMatch(m, /^Subject: =\?UTF-8\?B\?/m);
  assertMatch(m, /\r\n\.\r\n$/);
  assertEquals((m.match(/Content-Transfer-Encoding: base64/g) ?? []).length, 2);
  assert(!/[^\r]\n/.test(m), "every line ends in CRLF");
});

Deno.test("asking for a code takes its allowance in the database, per number and per connection, before anything is sent", async () => {
  slotAnswer = true;
  const s = supabase("ok");
  try {
    await handler(post({ action: "send", mobile: "09171234567" }, { "cf-connecting-ip": "203.0.113.5" }));
    const buckets = s.calls.filter((c) => c.url.pathname === "/rest/v1/rpc/take_rate_slot").map((c) => JSON.parse(c.body).p_bucket);
    assert(buckets.includes("otp-ip:203.0.113.5"), "per connection");
    assert(buckets.includes("otp-all"), "whole service");
    assert(buckets.includes("otp-send:u1"), "per account");
    assert(!s.calls.some((c) => c.url.pathname === "/rest/v1/password_otps" && c.method === "GET" && c.url.searchParams.get("created_at")), "no read-then-write count");
  } finally { s.restore(); }
});

Deno.test("an exhausted allowance answers 429 for a number with an account and for one without, and sends nothing", async () => {
  slotAnswer = false;
  const s = supabase("ok");
  try {
    const known = await handler(post({ action: "send", mobile: "09171234567" }, { "cf-connecting-ip": "203.0.113.5" }));
    const unknown = await handler(post({ action: "send", mobile: "09179999999" }, { "cf-connecting-ip": "203.0.113.5" }));
    assertEquals(known.status, 429);
    assertEquals(unknown.status, 429);
    assertEquals((await known.json()).message, (await unknown.json()).message);
    assert(!s.calls.some((c) => c.url.hostname === "api.semaphore.co" || (c.url.pathname === "/rest/v1/password_otps" && c.method === "POST")), "no code is made or sent");
  } finally { slotAnswer = true; s.restore(); }
});
