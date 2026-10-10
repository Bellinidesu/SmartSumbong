// One-off (0117): moves identity photos uploaded before private storage
// (public ids/ and selfies/ assets) to Cloudinary "authenticated" delivery,
// and updates the stored addresses. Safe to run more than once.
//
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   CLOUDINARY_CLOUD_NAME=nwb2kryl CLOUDINARY_API_KEY=... CLOUDINARY_API_SECRET=... \
//   node scripts/privatize-identity-photos.mjs            # dry run: lists what it would move
//   node scripts/privatize-identity-photos.mjs --apply    # moves them
//
// A selfie that is also someone's profile picture (before 0117 avatars
// shared the selfies/ folder) is left public. Node 18+, no packages.
import { createHash } from "node:crypto";

const env = (k) => { const v = process.env[k]; if (!v) { console.error(`Missing ${k}`); process.exit(1); } return v; };
const SUPABASE_URL = env("SUPABASE_URL"), SERVICE = env("SUPABASE_SERVICE_ROLE_KEY");
const CLOUD = env("CLOUDINARY_CLOUD_NAME"), KEY = env("CLOUDINARY_API_KEY"), SECRET = env("CLOUDINARY_API_SECRET");
const apply = process.argv.includes("--apply");
const headers = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" };

const PUBLIC = new RegExp(`^https://res\\.cloudinary\\.com/${CLOUD}/image/upload/v[0-9]+/((ids|selfies)/[0-9a-f-]{36})\\.(jpg|jpeg|png|webp)$`);

async function rows(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers });
  if (!res.ok) throw new Error(`${path}: ${res.status} ${await res.text()}`);
  return res.json();
}

async function makePrivate(publicId) {
  const params = { from_public_id: publicId, to_public_id: publicId, timestamp: String(Math.floor(Date.now() / 1000)), to_type: "authenticated", type: "upload" };
  const toSign = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join("&");
  const body = new URLSearchParams({ ...params, api_key: KEY, signature: createHash("sha256").update(toSign + SECRET).digest("hex") });
  const res = await fetch(`https://api.cloudinary.com/v1_1/${CLOUD}/image/rename`, { method: "POST", body });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.message ?? `HTTP ${res.status}`);
  return `https://res.cloudinary.com/${CLOUD}/image/authenticated/v${json.version}/${json.public_id}.${json.format}`;
}

const users = await rows("users?select=id,id_image_url,selfie_url,avatar_url");
const requests = await rows("profile_requests?select=id,id_image_url&id_image_url=not.is.null");
const avatars = new Set(users.map((u) => u.avatar_url).filter(Boolean));

const jobs = [];
for (const u of users) {
  for (const col of ["id_image_url", "selfie_url"]) {
    const url = u[col];
    if (url && PUBLIC.test(url) && !avatars.has(url)) jobs.push({ table: "users", id: u.id, col, url });
  }
}
for (const r of requests) if (PUBLIC.test(r.id_image_url)) jobs.push({ table: "profile_requests", id: r.id, col: "id_image_url", url: r.id_image_url });

console.log(`${jobs.length} identity photo(s) still public${apply ? "" : " (dry run; add --apply to move them)"}`);
let moved = 0, failed = 0;
for (const j of jobs) {
  if (!apply) { console.log(`  would move ${j.table}.${j.col} ${j.url}`); continue; }
  try {
    const next = await makePrivate(PUBLIC.exec(j.url)[1]);
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${j.table}?id=eq.${j.id}`, { method: "PATCH", headers, body: JSON.stringify({ [j.col]: next }) });
    if (!res.ok) throw new Error(`moved in Cloudinary, but saving ${next} failed: ${res.status} ${await res.text()}`);
    moved++;
  } catch (e) {
    failed++;
    console.error(`  ${j.table}.${j.col} ${j.id}: ${e.message}`);
  }
}
if (apply) console.log(`moved ${moved}, failed ${failed}`);
process.exit(failed ? 1 : 0);
