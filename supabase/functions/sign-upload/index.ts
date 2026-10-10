// SmartSumbong — sign-upload (0109).
//
// POST { folder: "reports" | "dispatch" | "ids" | "selfies", video?: boolean }
//   -> { ok: true, fields: { api_key, timestamp, signature, public_id, ... } }
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
//
// Video only for reports and dispatch, as before. Answers 403/429 with a
// message the app can show; the app falls back to the unsigned preset only
// while that still exists in Cloudinary (see media_upload.dart).
//
// Runs with verify_jwt off (registration has no session). Secrets:
// CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET (`supabase secrets set`),
// plus SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY every function gets.

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

/** The signed-in caller's role, or null when signed out (or not allowed in). */
async function callerRole(req: Request): Promise<string | null> {
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
  return u.role as string;
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

/** Cloudinary's signature: SHA-1 of the sorted params, then the secret. */
async function sign(params: Record<string, string>): Promise<string> {
  const text = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join("&") + API_SECRET;
  const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ ok: false, message: "POST only" }, 405);
  if (!API_KEY || !API_SECRET) return json({ ok: false, message: "Uploads are not signed here yet." }, 503);
  try {
    const body = await req.json().catch(() => ({}));
    const folder = String(body.folder ?? "");
    const video = body.video === true;
    if (!["reports", "dispatch", "ids", "selfies"].includes(folder)) {
      return json({ ok: false, message: "Unknown folder" }, 400);
    }
    if (video && folder !== "reports" && folder !== "dispatch") {
      return json({ ok: false, message: "Only photos can be sent here." }, 400);
    }

    const role = await callerRole(req);
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
    };
    return json({ ok: true, fields: { ...params, api_key: API_KEY, signature: await sign(params) } });
  } catch (e) {
    console.error(e);
    return json({ ok: false, message: "Something went wrong. Try again." }, 500);
  }
});
