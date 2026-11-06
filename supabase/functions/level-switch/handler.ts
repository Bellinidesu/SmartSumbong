// SmartSumbong — level-switch (0162)
//
// The development team sees the portal as each rung of the ladder sees it by signing into their own test account for that rung
// (dev_test_accounts), with no password. Signing in as someone else needs the service role key, which the portal never holds, so
// this function does it, and only this:
//
//   1. Identify the caller from their own bearer token (GoTrue /auth/v1/user with the anon key).
//   2. With the service role, check the caller is a developer (users.is_dev), not suspended and not a test account themselves, and
//      that the rung asked for is one of THEIR linked test accounts, which is marked is_test.
//   3. Make a one-time sign-in for that account (GoTrue admin generate_link, magiclink: nothing is emailed) and trade it at once
//      for a session (/auth/v1/verify with the token hash). Record the switch (dev_level_switches).
//
// The answer is the test account's session; the portal keeps the developer's own session to come back to. A developer can only ever
// reach their own test accounts: never a real person's.
//
// Required secrets: none beyond what Supabase injects (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY).

import { logError } from "../_shared/log.ts";

const LEVELS = ["super", "captain", "committee", "moderator"];

function env(name: string): string {
  return Deno.env.get(name) ?? "";
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function service(): Record<string, string> {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  return { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
}

async function callerId(token: string): Promise<string | null> {
  const res = await fetch(`${env("SUPABASE_URL")}/auth/v1/user`, { headers: { apikey: env("SUPABASE_ANON_KEY"), Authorization: `Bearer ${token}` } });
  if (!res.ok) return null;
  const u = await res.json();
  return typeof u?.id === "string" ? u.id : null;
}

async function rows(path: string): Promise<Record<string, unknown>[]> {
  const res = await fetch(`${env("SUPABASE_URL")}/rest/v1/${path}`, { headers: service() });
  if (!res.ok) throw new Error(`read failed: ${res.status}`);
  return await res.json();
}

export async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Sign in first" }, 401);
  try {
    const level = String((await req.json().catch(() => ({})))?.level ?? "");
    if (!LEVELS.includes(level)) return json({ error: "No such rung" }, 400);

    const me = await callerId(token);
    if (!me) return json({ error: "Sign in first" }, 401);

    const [who] = await rows(`users?select=is_dev,is_test,is_suspended&id=eq.${me}`);
    if (!who || who.is_dev !== true || who.is_test === true || who.is_suspended === true) {
      return json({ error: "Only a member of the development team can do this" }, 403);
    }
    const [link] = await rows(`dev_test_accounts?select=account&owner=eq.${me}&level=eq.${level}`);
    if (!link) return json({ error: "No test account for that rung yet" }, 404);
    const [acct] = await rows(`users?select=email,is_test,role,is_suspended&id=eq.${link.account}`);
    if (!acct || acct.is_test !== true || acct.role !== "admin" || acct.is_suspended === true || typeof acct.email !== "string") {
      return json({ error: "That test account cannot be used" }, 409);
    }

    const gen = await fetch(`${env("SUPABASE_URL")}/auth/v1/admin/generate_link`, {
      method: "POST",
      headers: service(),
      body: JSON.stringify({ type: "magiclink", email: acct.email }),
    });
    if (!gen.ok) throw new Error(`generate_link failed: ${gen.status}`);
    const g = await gen.json();
    const hash = g?.hashed_token ?? g?.properties?.hashed_token;
    if (typeof hash !== "string" || !hash) throw new Error("generate_link gave no token");

    const ver = await fetch(`${env("SUPABASE_URL")}/auth/v1/verify`, {
      method: "POST",
      headers: { apikey: env("SUPABASE_ANON_KEY"), "Content-Type": "application/json" },
      body: JSON.stringify({ type: "magiclink", token_hash: hash }),
    });
    if (!ver.ok) throw new Error(`verify failed: ${ver.status}`);
    const session = await ver.json();
    if (typeof session?.access_token !== "string") throw new Error("verify gave no session");

    await fetch(`${env("SUPABASE_URL")}/rest/v1/dev_level_switches`, {
      method: "POST",
      headers: { ...service(), Prefer: "return=minimal" },
      body: JSON.stringify({ owner: me, level }),
    });

    return json({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      expires_in: session.expires_in,
      user: { id: session.user?.id },
    });
  } catch (e) {
    await logError("level-switch", e);
    return json({ error: "Could not switch. Try again." }, 500);
  }
}
