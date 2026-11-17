// SmartSumbong — forgot password by a 6-digit code (0085), by email since 0174.
//
// POST { action: "send",   mobile }                  -> emails a code to the account's confirmed email (texts it instead when
//                                                       there is none and SMS is set up)
// POST { action: "verify", mobile, code, password }  -> sets the new password
//
// Signed in (Authorization: Bearer <the user's token>), 0104:
// POST { action: "mobile_send",   mobile }  -> texts a code to the NEW number
// POST { action: "mobile_verify", code }    -> moves the account to it
//
// Signed in, 0174:
// POST { action: "email_send" }         -> emails a code to the email on the profile
// POST { action: "email_verify", code } -> marks that email confirmed (users.email_confirmed_at)
//
// The caller is signed out (that is the point), so this function runs with
// verify_jwt off and does its own checks. Sending always answers the same
// way whether or not the number has an account, so the endpoint cannot be
// used to find out who is registered. Codes are stored as an HMAC keyed
// with the service role key, expire after 10 minutes, allow 5 tries and
// work once; at most 3 codes per account per hour. Guesses are checked and
// counted in the database (otp_attempt, 0114), so parallel tries cannot
// share a count; a reset by code signs the account out everywhere.
//
// Which accounts exist (17 Nov 2026): signing up already says a number is taken, so the answer to "send" names where the code
// went, masked (a•••@gmail.com), and a number with no confirmed email (or no account) hears the same "No email on this
// account". Only an account with a confirmed email is told apart, and only by its first letter and domain.
//
// Secrets (set with `supabase secrets set`, DEPLOY.md): SMTP_USER (the Gmail address codes come from), SMTP_PASS (a Gmail app
// password, never the account password), SMTP_FROM_NAME (optional, the sender's name; "SmartSumbong · Barangay 183"), plus the
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY every function gets. SMS, the fallback: SEMAPHORE_API_KEY, and optionally
// SEMAPHORE_SENDER_NAME, a sender name Semaphore has approved for the account. Read on each request, so a secret set later
// needs no redeploy.

import { logError } from "../_shared/log.ts";
import { timedFetch } from "../_shared/fetch.ts";
import { compose, maskEmail, type Purpose } from "./email.ts";
import { type Connect, plainAddress, sendMail } from "./smtp.ts";
// every outside call gives up after 10 seconds (_shared/fetch.ts, 11 Nov 2026)
const fetch = timedFetch(10_000);

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const env = (k: string) => (Deno.env.get(k) ?? "").trim();

const CODE_MINUTES = 10;
const MAX_TRIES = 5;
const MAX_PER_HOUR = 3;
const SENT = "If that number has an account, a code is on its way. It expires in 10 minutes.";
const NO_EMAIL = "No email on this account. Add one in Edit Profile, or ask the barangay hall to reset it.";

// Gmail over implicit TLS (smtp.ts). The tests swap the connection for a pretend server.
let connect: Connect = (o) => Deno.connectTls(o);
export function useSmtpConnection(c: Connect) {
  connect = c;
}

/** The Gmail sender, or null while its secrets are not set. An app password is shown with spaces; they are not part of it. */
function smtp() {
  const user = env("SMTP_USER"), pass = env("SMTP_PASS").replace(/\s+/g, "");
  if (!user || !pass) return null;
  return { host: "smtp.gmail.com", port: 465, user, pass, fromName: env("SMTP_FROM_NAME") || "SmartSumbong · Barangay 183" };
}

/** One code by email. False (and logged) when it could not go. */
async function emailCode(to: string, purpose: Purpose, code: string, mobile: string, tanod: boolean): Promise<boolean> {
  const cfg = smtp();
  if (!cfg) return false;
  const m = compose(purpose, code, { minutes: CODE_MINUTES, mobile, tanod });
  try {
    await sendMail(cfg, { to, subject: m.subject, text: m.text, html: m.html }, connect);
    return true;
  } catch (e) {
    console.error("email not sent:", e instanceof Error ? e.message : e);
    await logError("password-otp", e);
    return false;
  }
}

const sameEmail = (a: string | null | undefined, b: string | null | undefined) =>
  (a ?? "").trim().toLowerCase() === (b ?? "").trim().toLowerCase();

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

const rest = (path: string, init: RequestInit = {}) =>
  fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });

/** 09XXXXXXXXX, 639XXXXXXXXX or +639XXXXXXXXX -> +639XXXXXXXXX, else null. */
function normalise(raw: unknown): string | null {
  const d = String(raw ?? "").replace(/[\s-]/g, "");
  if (/^09\d{9}$/.test(d)) return "+63" + d.slice(1);
  if (/^639\d{9}$/.test(d)) return "+" + d;
  if (/^\+639\d{9}$/.test(d)) return d;
  return null;
}

async function hmac(text: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(SERVICE_ROLE_KEY),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * A uniform 6-digit code. Draws are rejected above the largest multiple of
 * a million that fits in 32 bits, so every code is equally likely (a plain
 * % 1_000_000 would favour the low codes very slightly).
 */
export function sixDigits(): string {
  const limit = 4_294_000_000; // 4,294 x 1,000,000 <= 2^32
  let n: number;
  do {
    n = crypto.getRandomValues(new Uint32Array(1))[0];
  } while (n >= limit);
  return (n % 1_000_000).toString().padStart(6, "0");
}

/**
 * One guess at the newest live code (0114). The database checks it and
 * counts a wrong one under a row lock, so guesses sent in parallel cannot
 * share a try the way a read-then-write from here could.
 */
async function attempt(userId: string, purpose: "password" | "mobile" | "email", hash: string) {
  const res = await rest("rpc/otp_attempt", {
    method: "POST",
    body: JSON.stringify({ p_user: userId, p_purpose: purpose, p_hash: hash, p_max: MAX_TRIES }),
  });
  if (!res.ok) throw new Error(`otp_attempt failed: ${res.status} ${(await res.text()).slice(0, 200)}`);
  const row = (await res.json())[0];
  return {
    outcome: row?.outcome as "ok" | "wrong" | "expired",
    attempts_left: Number(row?.attempts_left ?? 0),
    otp_id: row?.otp_id as string,
    new_mobile: (row?.new_mobile ?? null) as string | null,
  };
}

function wrongTry(left: number): Response {
  return json({ ok: false, message: left > 0 ? `That code is not right. ${left} ${left === 1 ? "try" : "tries"} left.` : "Too many wrong tries. Ask for a new code." }, 400);
}

type Account = { id: string; role: string; email: string | null; email_confirmed_at: string | null };

/** The account a resident or tanod signs in with, or null. Admins reset through Supabase's own email. */
async function findAccount(mobile: string) {
  const res = await rest(
    `users?mobile_number=eq.${encodeURIComponent(mobile)}&role=in.(resident,tanod)` +
      `&select=id,role,email,email_confirmed_at,is_suspended,is_retired&limit=1`);
  if (!res.ok) throw new Error(`lookup failed: ${res.status}`);
  const rows = await res.json();
  const u = rows[0];
  if (!u || u.is_suspended || u.is_retired) return null;
  return u as Account;
}

/** Where a reset code for this account goes: its confirmed email, else SMS when that is set up, else nowhere. */
function channel(user: Account | null): "email" | "sms" | null {
  if (user?.email && user.email_confirmed_at && plainAddress(user.email.trim()) && smtp()) return "email";
  if (env("SEMAPHORE_API_KEY")) return "sms";
  return null;
}

async function send(mobile: string): Promise<Response> {
  const user = await findAccount(mobile);
  const via = channel(user);
  // A confirmed email the function cannot write to is the barangay's to fix: said in Recent errors.
  if (user?.email_confirmed_at && !smtp()) await logError("password-otp", "a reset code could not be emailed: SMTP_USER / SMTP_PASS are not set");
  // No account, or no way to reach it: the same answer either way.
  if (!via) return json({ ok: false, code: "no_email", message: NO_EMAIL });
  if (!user) return json({ ok: true, channel: "sms", message: SENT });

  const since = new Date(Date.now() - 3600_000).toISOString();
  const recent = await rest(
    `password_otps?user_id=eq.${user.id}&purpose=eq.password&created_at=gte.${encodeURIComponent(since)}&select=id`);
  if ((await recent.json()).length >= MAX_PER_HOUR) {
    return json({ ok: false, message: "Too many codes for this number. Try again in an hour, or visit the barangay hall." }, 429);
  }

  // A new code retires every earlier one.
  await rest(`password_otps?user_id=eq.${user.id}&purpose=eq.password&used_at=is.null`, {
    method: "PATCH",
    body: JSON.stringify({ used_at: new Date().toISOString() }),
  });

  const code = sixDigits();
  const ins = await rest("password_otps", {
    method: "POST",
    body: JSON.stringify({
      user_id: user.id,
      code_hash: await hmac(`${user.id}:${code}`),
      expires_at: new Date(Date.now() + CODE_MINUTES * 60_000).toISOString(),
    }),
  });
  if (!ins.ok) throw new Error(`could not store the code: ${ins.status}`);
  const row = (await ins.json())[0];

  const to = (user.email ?? "").trim();
  const sent = via === "email"
    ? await emailCode(to, "reset", code, mobile, user.role === "tanod")
    : await textCode(mobile, code);
  if (!sent) {
    await rest(`password_otps?id=eq.${row.id}`, { method: "DELETE" });
    return json({ ok: false, message: "We couldn't send the code right now. Try again in a few minutes, or visit the barangay hall." }, 502);
  }
  if (via === "sms") return json({ ok: true, channel: "sms", message: SENT });
  const masked = maskEmail(to);
  return json({ ok: true, channel: "email", to: masked, message: `We sent a code to the email on your account: ${masked}. It expires in ${CODE_MINUTES} minutes.` });
}

async function verify(mobile: string, code: string, password: string): Promise<Response> {
  if (!/^\d{6}$/.test(code)) return json({ ok: false, message: "Enter the 6-digit code we sent you." }, 400);
  if (password.length < 8) return json({ ok: false, message: "Use at least 8 characters for the new password." }, 400);

  const user = await findAccount(mobile);
  const wrong = json({ ok: false, message: "That code is wrong or has expired. Ask for a new one." }, 400);
  if (!user) return wrong;

  const otp = await attempt(user.id, "password", await hmac(`${user.id}:${code}`));
  if (otp.outcome === "expired") return wrong;
  if (otp.outcome !== "ok") return wrongTry(otp.attempts_left);

  const upd = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${user.id}`, {
    method: "PUT",
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  if (!upd.ok) {
    console.error("password update failed:", upd.status, (await upd.text()).slice(0, 300));
    await logError("password-otp", `password update failed (HTTP ${upd.status})`);
    return json({ ok: false, message: "Your password could not be changed. Try again." }, 500);
  }

  await rest(`password_otps?id=eq.${otp.otp_id}`, { method: "PATCH", body: JSON.stringify({ used_at: new Date().toISOString() }) });
  await rest(`users?id=eq.${user.id}`, { method: "PATCH", body: JSON.stringify({ must_change_password: false }) });
  // Whoever knew the old password is signed out everywhere (0114).
  const out = await rest("rpc/revoke_user_sessions", { method: "POST", body: JSON.stringify({ p_user: user.id }) });
  if (!out.ok) console.error("could not end old sessions:", out.status, (await out.text()).slice(0, 200));
  await rest("account_audit", {
    method: "POST",
    body: JSON.stringify({ subject_id: user.id, actor_id: user.id, action: "password_reset", detail: "Password reset with a one-time code" }),
  });
  return json({ ok: true, message: "Your password has been changed. Sign in with the new one." });
}

// Semaphore's OTP route, not its bulk one: codes go out on their own priority
// route and are not held behind ordinary messages. It takes our own code (the
// database keeps only its hash) and puts it where the message says {otp}.
// The route and its fields as in pravennn08/semaphore-sdk (MIT).
async function textCode(mobile: string, code: string): Promise<boolean> {
  const form = new URLSearchParams({
    apikey: env("SEMAPHORE_API_KEY"),
    number: "0" + mobile.slice(3),
    message: `Your SmartSumbong code is {otp}. It expires in ${CODE_MINUTES} minutes. Do not share it with anyone.`,
    code,
  });
  if (env("SEMAPHORE_SENDER_NAME")) form.set("sendername", env("SEMAPHORE_SENDER_NAME"));
  const sms = await fetch("https://api.semaphore.co/api/v4/otp", { method: "POST", body: form });
  const body = await sms.text();
  try {
    const parsed = JSON.parse(body);
    if (sms.ok && Array.isArray(parsed) && parsed[0]?.message_id) return true;
  } catch { /* falls through */ }
  console.error("semaphore refused:", sms.status, body.slice(0, 300));
  await logError("password-otp", `the SMS provider refused a code (HTTP ${sms.status})`);
  return false;
}

const signInAddress = (mobile: string) => `${mobile.replace(/\D/g, "")}@auth.smartsumbong.local`;

async function setSignIn(id: string, mobile: string): Promise<boolean> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${id}`, {
    method: "PUT",
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email: signInAddress(mobile), email_confirm: true }),
  });
  if (!res.ok) console.error("sign-in update failed:", res.status, (await res.text()).slice(0, 300));
  return res.ok;
}

/** The signed-in resident or tanod behind the request's token, or null. */
async function caller(req: Request) {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token || token === SERVICE_ROLE_KEY) return null;
  const who = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${token}` } });
  if (!who.ok) return null;
  const id = (await who.json()).id as string | undefined;
  if (!id) return null;
  const res = await rest(
    `users?id=eq.${id}&role=in.(resident,tanod)&select=id,role,mobile_number,email,email_confirmed_at,is_suspended,is_retired&limit=1`);
  const u = (await res.json())[0];
  if (!u || u.is_suspended || u.is_retired) return null;
  return u as Account & { mobile_number: string };
}

/** 0104: a code to the number the account is moving to. */
async function mobileSend(req: Request, mobile: string): Promise<Response> {
  const user = await caller(req);
  if (!user) return json({ ok: false, message: "Sign in again, then try." }, 401);
  if (user.mobile_number === mobile) return json({ ok: false, message: "That is already your number." }, 400);
  const taken = await rest(`users?mobile_number=eq.${encodeURIComponent(mobile)}&select=id&limit=1`);
  if ((await taken.json()).length) return json({ ok: false, message: "Another account already uses that number." }, 409);

  const since = new Date(Date.now() - 3600_000).toISOString();
  const recent = await rest(`password_otps?user_id=eq.${user.id}&purpose=eq.mobile&created_at=gte.${encodeURIComponent(since)}&select=id`);
  if ((await recent.json()).length >= MAX_PER_HOUR) {
    return json({ ok: false, message: "Too many codes. Try again in an hour." }, 429);
  }
  await rest(`password_otps?user_id=eq.${user.id}&purpose=eq.mobile&used_at=is.null`, {
    method: "PATCH", body: JSON.stringify({ used_at: new Date().toISOString() }),
  });
  const code = sixDigits();
  const ins = await rest("password_otps", {
    method: "POST",
    body: JSON.stringify({
      user_id: user.id,
      purpose: "mobile",
      new_mobile: mobile,
      code_hash: await hmac(`${user.id}:${mobile}:${code}`),
      expires_at: new Date(Date.now() + CODE_MINUTES * 60_000).toISOString(),
    }),
  });
  if (!ins.ok) throw new Error(`could not store the code: ${ins.status}`);
  const row = (await ins.json())[0];
  if (!await textCode(mobile, code)) {
    await rest(`password_otps?id=eq.${row.id}`, { method: "DELETE" });
    return json({ ok: false, message: "We couldn't send the code right now. Try again in a few minutes." }, 502);
  }
  return json({ ok: true, message: `A code was sent to 0${mobile.slice(3)}. It expires in ${CODE_MINUTES} minutes.` });
}

/** 0104: the right code moves the sign-in and the stored number together. */
async function mobileVerify(req: Request, code: string): Promise<Response> {
  if (!/^\d{6}$/.test(code)) return json({ ok: false, message: "Enter the 6-digit code from the text." }, 400);
  const user = await caller(req);
  if (!user) return json({ ok: false, message: "Sign in again, then try." }, 401);
  const wrong = json({ ok: false, message: "That code is wrong or has expired. Ask for a new one." }, 400);
  // The hash binds the code to the number it was sent to; read that number
  // first, then let otp_attempt check and count the guess under a lock.
  const res = await rest(
    `password_otps?user_id=eq.${user.id}&purpose=eq.mobile&used_at=is.null&order=created_at.desc&limit=1&select=new_mobile`);
  const pending = (await res.json())[0];
  if (!pending?.new_mobile) return wrong;
  const otp = await attempt(user.id, "mobile", await hmac(`${user.id}:${pending.new_mobile}:${code}`));
  if (otp.outcome === "wrong") return wrongTry(otp.attempts_left);
  if (otp.outcome !== "ok" || !otp.new_mobile) return wrong;
  const mobile = otp.new_mobile;
  // The app signs in with an address made from the number (auth.dart, authEmailFor).
  if (!await setSignIn(user.id, mobile)) return json({ ok: false, message: "Your number could not be changed. Try again." }, 500);
  const row = await rest(`users?id=eq.${user.id}`, { method: "PATCH", body: JSON.stringify({ mobile_number: mobile }) });
  if (!row.ok) {
    // Put the sign-in back so the account is never split between numbers.
    await setSignIn(user.id, user.mobile_number);
    return json({ ok: false, message: "Another account already uses that number." }, 409);
  }
  await rest(`password_otps?id=eq.${otp.otp_id}`, { method: "PATCH", body: JSON.stringify({ used_at: new Date().toISOString() }) });
  await rest("account_audit", {
    method: "POST",
    body: JSON.stringify({ subject_id: user.id, actor_id: user.id, action: "mobile_changed", detail: "Mobile number changed with an SMS code" }),
  });
  await rest("notifications", {
    method: "POST",
    body: JSON.stringify({ user_id: user.id, kind: "status_change", message: "Your mobile number was changed. Sign in with the new number from now on." }),
  });
  return json({ ok: true, mobile, message: "Your number has been changed. Sign in with it from now on." });
}

/** 0174: a code to the email on the profile, so the person shows they read it. */
async function emailSend(req: Request): Promise<Response> {
  const user = await caller(req);
  if (!user) return json({ ok: false, message: "Sign in again, then try." }, 401);
  const to = (user.email ?? "").trim();
  if (!to) return json({ ok: false, message: "Add your email and save it first." }, 400);
  if (!plainAddress(to)) return json({ ok: false, message: "That email does not look right. Fix it and save it first." }, 400);
  if (user.email_confirmed_at) return json({ ok: true, already: true, message: "Your email is already confirmed." });
  if (!smtp()) {
    await logError("password-otp", "an email could not be confirmed: SMTP_USER / SMTP_PASS are not set");
    return json({ ok: false, message: "Email is not set up yet. Try again later." }, 503);
  }

  const since = new Date(Date.now() - 3600_000).toISOString();
  const recent = await rest(`password_otps?user_id=eq.${user.id}&purpose=eq.email&created_at=gte.${encodeURIComponent(since)}&select=id`);
  if ((await recent.json()).length >= MAX_PER_HOUR) {
    return json({ ok: false, message: "Too many codes. Try again in an hour." }, 429);
  }
  await rest(`password_otps?user_id=eq.${user.id}&purpose=eq.email&used_at=is.null`, {
    method: "PATCH",
    body: JSON.stringify({ used_at: new Date().toISOString() }),
  });
  const code = sixDigits();
  const ins = await rest("password_otps", {
    method: "POST",
    body: JSON.stringify({
      user_id: user.id,
      purpose: "email",
      new_email: to,
      code_hash: await hmac(`${user.id}:${to.toLowerCase()}:${code}`),
      expires_at: new Date(Date.now() + CODE_MINUTES * 60_000).toISOString(),
    }),
  });
  if (!ins.ok) throw new Error(`could not store the code: ${ins.status}`);
  const row = (await ins.json())[0];
  if (!await emailCode(to, "confirm", code, user.mobile_number, user.role === "tanod")) {
    await rest(`password_otps?id=eq.${row.id}`, { method: "DELETE" });
    return json({ ok: false, message: "We couldn't send the email right now. Check the address, or try again in a few minutes." }, 502);
  }
  const masked = maskEmail(to);
  return json({ ok: true, to: masked, message: `We sent a code to ${masked}. It expires in ${CODE_MINUTES} minutes.` });
}

/** 0174: the right code marks the email confirmed, as long as it is still the address the code went to. */
async function emailVerify(req: Request, code: string): Promise<Response> {
  if (!/^\d{6}$/.test(code)) return json({ ok: false, message: "Enter the 6-digit code from the email." }, 400);
  const user = await caller(req);
  if (!user) return json({ ok: false, message: "Sign in again, then try." }, 401);
  const wrong = json({ ok: false, message: "That code is wrong or has expired. Ask for a new one." }, 400);
  const res = await rest(
    `password_otps?user_id=eq.${user.id}&purpose=eq.email&used_at=is.null&order=created_at.desc&limit=1&select=new_email`);
  const pending = (await res.json())[0];
  if (!pending?.new_email) return wrong;
  const otp = await attempt(user.id, "email", await hmac(`${user.id}:${String(pending.new_email).trim().toLowerCase()}:${code}`));
  if (otp.outcome === "wrong") return wrongTry(otp.attempts_left);
  if (otp.outcome !== "ok") return wrong;
  const done = () =>
    rest(`password_otps?id=eq.${otp.otp_id}`, { method: "PATCH", body: JSON.stringify({ used_at: new Date().toISOString() }) });
  const changed = json({ ok: false, message: "Your email changed after the code was sent. Ask for a new code." }, 409);
  if (!user.email || !sameEmail(user.email, pending.new_email)) {
    await done();
    return changed;
  }
  // Only while the email is still the one the code went to (a save in between clears the mark anyway, 0174).
  const upd = await rest(`users?id=eq.${user.id}&email=eq.${encodeURIComponent(user.email)}`, {
    method: "PATCH",
    body: JSON.stringify({ email_confirmed_at: new Date().toISOString() }),
  });
  if (!upd.ok) throw new Error(`could not confirm the email: ${upd.status}`);
  await done();
  if (!(await upd.json()).length) return changed;
  await rest("account_audit", {
    method: "POST",
    body: JSON.stringify({ subject_id: user.id, actor_id: user.id, action: "email_confirmed", detail: "Email confirmed with a one-time code" }),
  });
  return json({ ok: true, message: "Your email is confirmed. Password reset codes will come here." });
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ ok: false, message: "POST only" }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    if (body.action === "mobile_verify") return await mobileVerify(req, String(body.code ?? ""));
    if (body.action === "email_send") return await emailSend(req);
    if (body.action === "email_verify") return await emailVerify(req, String(body.code ?? ""));
    const mobile = normalise(body.mobile);
    if (!mobile) return json({ ok: false, message: "Enter your mobile number as 09XXXXXXXXX." }, 400);
    if (body.action === "send") return await send(mobile);
    if (body.action === "verify") return await verify(mobile, String(body.code ?? ""), String(body.password ?? ""));
    if (body.action === "mobile_send") return await mobileSend(req, mobile);
    return json({ ok: false, message: "Unknown action" }, 400);
  } catch (e) {
    console.error(e);
    await logError("password-otp", e);
    return json({ ok: false, message: "Something went wrong. Try again, or visit the barangay hall." }, 500);
  }
}
