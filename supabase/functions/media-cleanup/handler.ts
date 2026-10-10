// SmartSumbong — media-cleanup (0111).
//
// Deletes identity photos (ids/, selfies/, avatars/) that nothing has used
// for a week: a deleted account's ID and selfie, an ID replaced or
// declined, a replaced profile picture. The database decides which
// (media_trash_due(), which re-checks every address is still unused); this
// only removes the files from Cloudinary and reports back. Complaint and
// dispatch evidence never reaches the queue.
//
// Called once a day by pg_cron (run_media_cleanup(), 0111) with the shared
// secret in x-cleanup-secret. verify_jwt is off: the secret is the check.
// Secrets: MEDIA_CLEANUP_SECRET, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET,
// plus SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY every function gets.

import { logError } from "../_shared/log.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CLEANUP_SECRET = Deno.env.get("MEDIA_CLEANUP_SECRET") ?? "";
const API_KEY = Deno.env.get("CLOUDINARY_API_KEY") ?? "";
const API_SECRET = Deno.env.get("CLOUDINARY_API_SECRET") ?? "";

const service = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
  "Content-Type": "application/json",
};

/** cloud, delivery type and public id of a queued address, or null. */
export function parse(url: string): { cloud: string; type: string; publicId: string } | null {
  const m = /^https:\/\/res\.cloudinary\.com\/([a-z0-9_-]+)\/image\/(upload|authenticated)\/v[0-9]+\/((ids|selfies|avatars)\/[0-9a-f-]{36})\.[a-z]+$/
    .exec(url);
  return m ? { cloud: m[1], type: m[2], publicId: m[3] } : null;
}

export async function apiSignature(params: Record<string, string>, secret: string): Promise<string> {
  const text = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join("&") + secret;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sameSecret(sent: string): boolean {
  if (!CLEANUP_SECRET || sent.length !== CLEANUP_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < sent.length; i++) diff |= sent.charCodeAt(i) ^ CLEANUP_SECRET.charCodeAt(i);
  return diff === 0;
}

/** Deletes one file. True when it is gone (deleted now, or already). */
async function destroy(url: string): Promise<boolean> {
  const a = parse(url);
  if (!a) return true; // not ours to delete; drop it from the queue
  const params = { invalidate: "true", public_id: a.publicId, timestamp: String(Math.floor(Date.now() / 1000)), type: a.type };
  const body = new URLSearchParams({ ...params, api_key: API_KEY, signature: await apiSignature(params, API_SECRET) });
  const res = await fetch(`https://api.cloudinary.com/v1_1/${a.cloud}/image/destroy`, { method: "POST", body });
  const json = await res.json().catch(() => ({}));
  if (res.ok && (json.result === "ok" || json.result === "not found")) return true;
  console.error("destroy failed:", url, res.status, JSON.stringify(json).slice(0, 200));
  await logError("media-cleanup", `Cloudinary refused to delete a photo (HTTP ${res.status})`);
  return false;
}

export async function handler(req: Request): Promise<Response> {
  if (!sameSecret(req.headers.get("x-cleanup-secret") ?? "")) return new Response("forbidden", { status: 403 });
  if (!API_KEY || !API_SECRET) return new Response("Cloudinary key not set", { status: 503 });
  try {
    const due = await fetch(`${SUPABASE_URL}/rest/v1/rpc/media_trash_due`, {
      method: "POST", headers: service, body: JSON.stringify({ p_limit: 100 }),
    });
    if (!due.ok) throw new Error(`media_trash_due: ${due.status} ${await due.text()}`);
    const urls = (await due.json()) as string[];
    const gone: string[] = [];
    for (const url of urls) if (await destroy(url)) gone.push(url);
    const done = await fetch(`${SUPABASE_URL}/rest/v1/rpc/media_trash_done`, {
      method: "POST", headers: service, body: JSON.stringify({ p_urls: gone }),
    });
    if (!done.ok) throw new Error(`media_trash_done: ${done.status} ${await done.text()}`);
    return Response.json({ due: urls.length, deleted: gone.length });
  } catch (e) {
    console.error("media-cleanup failed:", e);
    await logError("media-cleanup", e);
    return new Response("error, see function logs", { status: 500 });
  }
}
