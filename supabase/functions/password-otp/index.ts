// SmartSumbong — forgot password by SMS code (0085).
//
// POST { action: "send",   mobile }                  -> texts a 6-digit code
// POST { action: "verify", mobile, code, password }  -> sets the new password
//
// The caller is signed out (that is the point), so this function runs with
// verify_jwt off and does its own checks. Sending always answers the same
// way whether or not the number has an account, so the endpoint cannot be
// used to find out who is registered. Codes are stored as an HMAC keyed
// with the service role key, expire after 10 minutes, allow 5 tries and
// work once; at most 3 codes per account per hour.
//
// Secrets: SEMAPHORE_API_KEY (set with `supabase secrets set`), plus the
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY every function gets.

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

function sixDigits(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
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
    `password_otps?user_id=eq.${user.id}&created_at=gte.${encodeURIComponent(since)}&select=id`);
  if ((await recent.json()).length >= MAX_PER_HOUR) {
    return json({ ok: false, message: "Too many codes for this number. Try again in an hour, or visit the barangay hall." }, 429);
  }

  // A new code retires every earlier one.
  await rest(`password_otps?user_id=eq.${user.id}&used_at=is.null`, {
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

  const form = new URLSearchParams({
    apikey: SEMAPHORE_API_KEY,
    number: "0" + mobile.slice(3),
    message: `Your SmartSumbong code is ${code}. It expires in ${CODE_MINUTES} minutes. Do not share it with anyone.`,
  });
  const sms = await fetch("https://api.semaphore.co/api/v4/messages", { method: "POST", body: form });
  const smsBody = await sms.text();
  let accepted = sms.ok;
  try {
    const parsed = JSON.parse(smsBody);
    if (!Array.isArray(parsed) || !parsed[0]?.message_id) accepted = false;
  } catch {
    accepted = false;
  }
  if (!accepted) {
    console.error("semaphore refused:", sms.status, smsBody.slice(0, 300));
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

  const res = await rest(
    `password_otps?user_id=eq.${user.id}&used_at=is.null&order=created_at.desc&limit=1&select=id,code_hash,expires_at,attempts`);
  const otp = (await res.json())[0];
  if (!otp || new Date(otp.expires_at).getTime() < Date.now() || otp.attempts >= MAX_TRIES) return wrong;

  if (otp.code_hash !== await hmac(`${user.id}:${code}`)) {
    await rest(`password_otps?id=eq.${otp.id}`, {
      method: "PATCH",
      body: JSON.stringify({ attempts: otp.attempts + 1 }),
    });
    const left = MAX_TRIES - otp.attempts - 1;
    return json({ ok: false, message: left > 0 ? `That code is not right. ${left} ${left === 1 ? "try" : "tries"} left.` : "Too many wrong tries. Ask for a new code." }, 400);
  }

  const upd = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${user.id}`, {
    method: "PUT",
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  if (!upd.ok) {
    console.error("password update failed:", upd.status, (await upd.text()).slice(0, 300));
    return json({ ok: false, message: "Your password could not be changed. Try again." }, 500);
  }

  await rest(`password_otps?id=eq.${otp.id}`, { method: "PATCH", body: JSON.stringify({ used_at: new Date().toISOString() }) });
  await rest(`users?id=eq.${user.id}`, { method: "PATCH", body: JSON.stringify({ must_change_password: false }) });
  await rest("account_audit", {
    method: "POST",
    body: JSON.stringify({ subject_id: user.id, actor_id: user.id, action: "password_reset", detail: "Password reset with an SMS code" }),
  });
  return json({ ok: true, message: "Your password has been changed. Sign in with the new one." });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ ok: false, message: "POST only" }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    const mobile = normalise(body.mobile);
    if (!mobile) return json({ ok: false, message: "Enter your mobile number as 09XXXXXXXXX." }, 400);
    if (body.action === "send") return await send(mobile);
    if (body.action === "verify") return await verify(mobile, String(body.code ?? ""), String(body.password ?? ""));
    return json({ ok: false, message: "Unknown action" }, 400);
  } catch (e) {
    console.error(e);
    return json({ ok: false, message: "Something went wrong. Try again, or visit the barangay hall." }, 500);
  }
});
