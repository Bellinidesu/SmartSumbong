// SmartSumbong — forgot password by SMS code (0085).
//
// POST { action: "send",   mobile }                  -> texts a 6-digit code
// POST { action: "verify", mobile, code, password }  -> sets the new password
//
// Signed in (Authorization: Bearer <the user's token>), 0104:
// POST { action: "mobile_send",   mobile }  -> texts a code to the NEW number
// POST { action: "mobile_verify", code }    -> moves the account to it
//
// The caller is signed out (that is the point), so this function runs with
// verify_jwt off and does its own checks. Sending always answers the same
// way whether or not the number has an account, so the endpoint cannot be
// used to find out who is registered. Codes are stored as an HMAC keyed
// with the service role key, expire after 10 minutes, allow 5 tries and
// work once; at most 3 codes per account per hour. Guesses are checked and
// counted in the database (otp_attempt, 0107), so parallel tries cannot
// share a count; a reset by code signs the account out everywhere.
//
// Secrets: SEMAPHORE_API_KEY (set with `supabase secrets set`), plus the
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY every function gets.

import { logError } from "../_shared/log.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SEMAPHORE_API_KEY = Deno.env.get("SEMAPHORE_API_KEY") ?? "";

const CODE_MINUTES = 10;
const MAX_TRIES = 5;
const MAX_PER_HOUR = 3;
const SENT = "If that number has an account, a code is on its way. It expires in 10 minutes.";

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
 * One guess at the newest live code (0107). The database checks it and
 * counts a wrong one under a row lock, so guesses sent in parallel cannot
 * share a try the way a read-then-write from here could.
 */
async function attempt(userId: string, purpose: "password" | "mobile", hash: string) {
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

/** The account a resident or tanod signs in with, or null. Admins reset by email. */
async function findAccount(mobile: string) {
  const res = await rest(
    `users?mobile_number=eq.${encodeURIComponent(mobile)}&role=in.(resident,tanod)` +
      `&select=id,is_suspended,is_retired&limit=1`);
  if (!res.ok) throw new Error(`lookup failed: ${res.status}`);
  const rows = await res.json();
  const u = rows[0];
  if (!u || u.is_suspended || u.is_retired) return null;
  return u as { id: string };
}

async function send(mobile: string): Promise<Response> {
  const user = await findAccount(mobile);
  if (!user) return json({ ok: true, message: SENT });

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

  if (!await textCode(mobile, code)) {
    await rest(`password_otps?id=eq.${row.id}`, { method: "DELETE" });
    return json({ ok: false, message: "We couldn't send the code right now. Try again in a few minutes, or visit the barangay hall." }, 502);
  }
  return json({ ok: true, message: SENT });
}

async function verify(mobile: string, code: string, password: string): Promise<Response> {
  if (!/^\d{6}$/.test(code)) return json({ ok: false, message: "Enter the 6-digit code from the text." }, 400);
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
  // Whoever knew the old password is signed out everywhere (0107).
  const out = await rest("rpc/revoke_user_sessions", { method: "POST", body: JSON.stringify({ p_user: user.id }) });
  if (!out.ok) console.error("could not end old sessions:", out.status, (await out.text()).slice(0, 200));
  await rest("account_audit", {
    method: "POST",
    body: JSON.stringify({ subject_id: user.id, actor_id: user.id, action: "password_reset", detail: "Password reset with an SMS code" }),
  });
  return json({ ok: true, message: "Your password has been changed. Sign in with the new one." });
}

async function textCode(mobile: string, code: string): Promise<boolean> {
  const form = new URLSearchParams({
    apikey: SEMAPHORE_API_KEY,
    number: "0" + mobile.slice(3),
    message: `Your SmartSumbong code is ${code}. It expires in ${CODE_MINUTES} minutes. Do not share it with anyone.`,
  });
  const sms = await fetch("https://api.semaphore.co/api/v4/messages", { method: "POST", body: form });
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
  const res = await rest(`users?id=eq.${id}&role=in.(resident,tanod)&select=id,mobile_number,is_suspended,is_retired&limit=1`);
  const u = (await res.json())[0];
  if (!u || u.is_suspended || u.is_retired) return null;
  return u as { id: string; mobile_number: string };
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

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ ok: false, message: "POST only" }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    if (body.action === "mobile_verify") return await mobileVerify(req, String(body.code ?? ""));
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
