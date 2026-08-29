// SmartSumbong — delete-account
//
// The self-service account deletion request_account_deletion() (migration
// 0045) can't finish on its own: it runs inside Postgres and can tell you
// whether it's safe to remove the auth.users row entirely or whether it
// scrubbed the resident's profile in place instead, but actually deleting
// or banning an auth user only works through GoTrue's Admin API, which
// needs the service role key — a value that must never be reachable from
// a database function an authenticated resident can call directly. This
// function is the other half: it holds that key, and does only the two
// things that require it.
//
// Same raw-fetch style as send-dispatch-push/index.ts (no supabase-js
// import) for consistency — one convention for talking to Supabase's REST
// and Admin APIs from an Edge Function in this codebase, not two.
//
// Flow:
//   1. Identify the caller from their own bearer token (GoTrue's own
//      /auth/v1/user, using the anon key — never the service role for
//      this step, so this function can only ever act on whoever the
//      token actually belongs to).
//   2. Call request_account_deletion() AS that caller (their token, not
//      the service role) — Postgres does the "has reports" decision and
//      the scrub, this function has no opinion on either.
//   3. Only now switch to the service role, and only for the one GoTrue
//      Admin call the RPC's answer says is needed: hard-delete when safe,
//      otherwise a ~100-year ban (GoTrue's ban_duration has no literal
//      "forever" — this is the documented practical workaround).
//
// Required secrets: none beyond what Supabase already injects into every
// Edge Function (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY)
// — confirmed current as of Aug 2026 against Supabase's own Edge
// Functions secrets documentation.
//
// NOT SMOKE-TESTED end to end (no live Supabase project reachable from
// where this was written) — verified only as: valid TypeScript (tsc
// --noEmit, "Deno" itself is the only undeclared name), and every
// endpoint shape and the ban_duration format checked against Supabase's
// current Admin API docs. Worth a real signed-in test account (one with
// zero reports, one with at least one) before trusting this in
// production — see the deploy notes.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function callerUserId(token: string): Promise<string> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    throw new Error(`Could not identify the caller: ${await res.text()}`);
  }
  const user = await res.json();
  if (!user?.id) throw new Error("No user on this session");
  return user.id as string;
}

/// Runs request_account_deletion() with the CALLER's own token, never the
/// service role — the function itself is SECURITY DEFINER and checks
/// auth.uid() internally, so it only ever touches the caller's own row
/// regardless, but using their token here (rather than the service role)
/// keeps that true structurally, not just by the function's own promise.
async function requestDeletion(token: string): Promise<boolean> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/rpc/request_account_deletion`,
    {
      method: "POST",
      headers: {
        apikey: ANON_KEY,
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    },
  );
  if (!res.ok) {
    throw new Error(`request_account_deletion failed: ${await res.text()}`);
  }
  // A `returns boolean` RPC comes back as the bare JSON literal true/false.
  return (await res.json()) === true;
}

async function hardDeleteAuthUser(uid: string): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${uid}`, {
    method: "DELETE",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });
  if (!res.ok) {
    throw new Error(`Could not delete the auth user: ${await res.text()}`);
  }
}

async function banAuthUserIndefinitely(uid: string): Promise<void> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${uid}`, {
    method: "PUT",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    // GoTrue's ban_duration is a Go duration string with no "forever"
    // value — 100 years (876000h) is the documented practical stand-in,
    // same as everyone else banning a user indefinitely on this platform.
    body: JSON.stringify({ ban_duration: "876000h" }),
  });
  if (!res.ok) {
    throw new Error(`Could not ban the auth user: ${await res.text()}`);
  }
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Missing session" }, 401);

    const uid = await callerUserId(token);
    const eligibleForHardDelete = await requestDeletion(token);

    if (eligibleForHardDelete) {
      await hardDeleteAuthUser(uid);
    } else {
      // public.users.id (still referenced by this resident's own kept
      // reports) is untouched by a ban — only sign-in is disabled.
      await banAuthUserIndefinitely(uid);
    }

    return json({ ok: true, hard_deleted: eligibleForHardDelete });
  } catch (e) {
    console.error("delete-account failed:", e);
    return json({ error: String(e) }, 400);
  }
});
