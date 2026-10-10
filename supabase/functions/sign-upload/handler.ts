// SmartSumbong — sign-upload (0116).
//
// POST { folder: "reports" | "dispatch" | "ids" | "selfies" | "avatars", video?: boolean }
//   -> { ok: true, fields: { api_key, timestamp, signature, public_id, ... } }
// POST { view: "<a stored ids/ or selfies/ address>" }               (0117)
//   -> { ok: true, url: "<a link that opens it>" }
//
// The app adds `fields` and the file to its multipart POST to Cloudinary's
// image or video upload endpoint, instead of an unsigned preset. This
// function picks every signed value, the file name (folder/<uuid>), the
// formats and the resize, so a caller cannot change them, and only signs a
// folder the caller is entitled to:
//
//   reports           a signed-in resident (complaint evidence)
//   dispatch          a signed-in tanod (field proof)
//   ids, selfies      anyone signed in; or, during registration, before any
//                     account exists, at most 10 per network address an hour
//   avatars           anyone signed in (profile pictures, public)
//
// ids/ and selfies/ are stored private (Cloudinary "authenticated", 0117):
// their stored address opens nothing. `view` signs a link for the photo's
// owner or an administrator; the portal signs its own.
//
// Video only for reports and dispatch, as before. Answers 403/429 with a
// message the app can show; the app falls back to the unsigned preset only
// while that still exists in Cloudinary (see media_upload.dart).
//
// Runs with verify_jwt off (registration has no session). Secrets:
// CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET (`supabase secrets set`),
// plus SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY every function gets.

import { logError } from "../_shared/log.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const API_KEY = Deno.env.get("CLOUDINARY_API_KEY") ?? "";
const API_SECRET = Deno.env.get("CLOUDINARY_API_SECRET") ?? "";

const PRE_ACCOUNT_PER_HOUR = 10;

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

const service = { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` };

/** The signed-in caller, or null when signed out (or not allowed in). */
async function caller(req: Request): Promise<{ id: string; role: string } | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token || token === SERVICE_ROLE_KEY) return null;
  const who = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${token}` },
  });
  if (!who.ok) return null; // the publishable key, or an expired session
  const id = (await who.json()).id as string | undefined;
  if (!id) return null;
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${id}&select=role,is_suspended,is_retired&limit=1`,
    { headers: service },
  );
  const u = res.ok ? (await res.json())[0] : null;
  if (!u || u.is_suspended || u.is_retired) return null;
  return { id, role: u.role as string };
}

const PRIVATE_URL =
  /^https:\/\/res\.cloudinary\.com\/([a-z0-9_-]+)\/image\/authenticated\/v[0-9]+\/((ids|selfies)\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp))$/;

/**
 * Cloudinary's signed delivery link: SHA-256 of the asset path and the
 * secret, its first 8 characters (the account signs with SHA-256).
 */
export async function signedView(url: string): Promise<string> {
  const m = PRIVATE_URL.exec(url)!;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(m[2] + API_SECRET));
  const sig = btoa(String.fromCharCode(...new Uint8Array(digest))).slice(0, 8)
    .replace(/\//g, "_").replace(/\+/g, "-");
  return url.replace("/image/authenticated/", `/image/authenticated/s--${sig}--/`);
}

/** May this caller see this private photo? Their own, or any for an admin. */
async function mayView(who: { id: string; role: string }, url: string): Promise<boolean> {
  if (who.role === "admin") return true;
  const enc = encodeURIComponent(url);
  const quoted = encodeURIComponent(`"${url}"`); // inside or=(), values with . and : are quoted
  const own = await fetch(
    `${SUPABASE_URL}/rest/v1/users?id=eq.${who.id}&or=(id_image_url.eq.${quoted},selfie_url.eq.${quoted})&select=id`,
    { headers: service },
  );
  if (own.ok && (await own.json()).length) return true;
  const asked = await fetch(
    `${SUPABASE_URL}/rest/v1/profile_requests?user_id=eq.${who.id}&id_image_url=eq.${enc}&select=id`,
    { headers: service },
  );
  return asked.ok && (await asked.json()).length > 0;
}

async function takeSlot(bucket: string, max: number): Promise<boolean> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/take_rate_slot`, {
    method: "POST",
    headers: { ...service, "Content-Type": "application/json" },
    body: JSON.stringify({ p_bucket: bucket, p_max: max, p_window: "1 hour" }),
  });
  if (!res.ok) throw new Error(`take_rate_slot failed: ${res.status}`);
  return (await res.json()) === true;
}

/** Cloudinary's signature: SHA-256 of the sorted params, then the secret. */
export async function sign(params: Record<string, string>): Promise<string> {
  const text = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join("&") + API_SECRET;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ ok: false, message: "POST only" }, 405);
  if (!API_KEY || !API_SECRET) return json({ ok: false, message: "Uploads are not signed here yet." }, 503);
  try {
    const body = await req.json().catch(() => ({}));

    if (typeof body.view === "string") {
      const who = await caller(req);
      if (!who) return json({ ok: false, message: "Sign in again, then try." }, 403);
      if (!PRIVATE_URL.test(body.view) || !await mayView(who, body.view)) {
        return json({ ok: false, message: "That photo is not yours to open." }, 403);
      }
      return json({ ok: true, url: await signedView(body.view) });
    }

    const folder = String(body.folder ?? "");
    const video = body.video === true;
    if (!["reports", "dispatch", "ids", "selfies", "avatars"].includes(folder)) {
      return json({ ok: false, message: "Unknown folder" }, 400);
    }
    if (video && folder !== "reports" && folder !== "dispatch") {
      return json({ ok: false, message: "Only photos can be sent here." }, 400);
    }

    const role = (await caller(req))?.role ?? null;
    const allowed =
      folder === "reports" ? role === "resident"
      : folder === "dispatch" ? role === "tanod"
      : role !== null;
    if (!allowed) {
      if (folder === "ids" || folder === "selfies") {
        // Registration: no account yet. Rationed per address instead.
        const addr = req.headers.get("cf-connecting-ip") ??
          (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
        if (!await takeSlot(`upload-ids:${addr || "unknown"}`, PRE_ACCOUNT_PER_HOUR)) {
          return json({ ok: false, message: "Too many photos sent from this connection. Try again in an hour." }, 429);
        }
      } else {
        return json({ ok: false, message: "Sign in again, then try." }, 403);
      }
    }

    // What the unsigned presets did, now fixed by the signature:
    // photos are resized to 1920 wide and stored as JPEG; video is mp4.
    const params: Record<string, string> = {
      public_id: `${folder}/${crypto.randomUUID()}`,
      timestamp: String(Math.floor(Date.now() / 1000)),
      ...(video
        ? { allowed_formats: "mp4" }
        : { allowed_formats: "jpg,png,webp", format: "jpg", transformation: "c_limit,w_1920,q_auto" }),
      // Identity photos are private (0117): only a signed link opens them.
      ...(folder === "ids" || folder === "selfies" ? { type: "authenticated" } : {}),
    };
    return json({ ok: true, fields: { ...params, api_key: API_KEY, signature: await sign(params) } });
  } catch (e) {
    console.error(e);
    await logError("sign-upload", e);
    return json({ ok: false, message: "Something went wrong. Try again." }, 500);
  }
}
