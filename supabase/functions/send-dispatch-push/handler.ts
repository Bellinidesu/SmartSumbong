// SmartSumbong — send-dispatch-push
//
// The other half of the push notification gap found during QA: the
// notifications table has always been the resident/tanod's in-app inbox,
// but nothing ever turned a new row into an actual phone banner. This
// function is that turn. It is wired up as a Supabase Database Webhook
// on INSERT to public.notifications (configured in the Dashboard, not in
// SQL — see the deploy notes, which is also where the required secrets
// are listed) so every new notification calls this function once, and
// this function looks up that user's registered devices (device_tokens,
// migration 0035) and pushes to each one over Firebase Cloud Messaging's
// HTTP v1 API.
//
// FCM's v1 API requires a short-lived OAuth2 access token, not a fixed
// API key, and Deno has no Firebase Admin SDK -- so this signs its own
// service-account JWT with the Web Crypto API and exchanges it for a
// token directly against Google's OAuth endpoint. That JWT-signing block
// is the least conventional part of this file and the part most worth
// smoke-testing by hand once deployed (see the deploy notes' curl
// command) before trusting it end to end.
//
// Required secrets (`supabase secrets set NAME=value`), on top of
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, which Supabase already
// injects into every Edge Function automatically:
//   FCM_PROJECT_ID    -- the Firebase project's project_id
//   FCM_CLIENT_EMAIL  -- the service account's client_email
//   FCM_PRIVATE_KEY   -- the service account's private_key, PEM, with its
//                        literal "\n" line breaks left intact as written
//                        by `supabase secrets set --env-file` or pasted
//                        as a single-line value with \n escapes
//
// A failure anywhere in here (bad token, unregistered device, network
// blip) is swallowed per-token and logged, never thrown back at the
// webhook caller -- a push failing must never look like the notifications
// insert itself failed, since that row already exists and already did
// its job of being the resident's or tanod's in-app record regardless of
// whether a phone ever buzzed.
//
// LIVE-UPDATING TRAY NOTIFICATIONS (added 29 Aug 2026, explicit ask: a
// resident should be able to file a report, back out to their phone's
// home screen, and just pull down the shade to see the CURRENT status
// rather than a pile of every status the report has ever had). Every
// report-linked push now carries android.notification.tag = report_id.
// Two Android notifications with the same tag replace each other in the
// drawer -- this is the one thing that works even when the app is fully
// backgrounded or killed, because that case is drawn entirely by Android
// itself from this payload; no Dart code runs to do it (see
// firebaseMessagingBackgroundHandler's own comment in push_notifications.
// dart). collapse_key rides along for the same report id so a device
// that was offline only replays the latest status once it reconnects,
// not every state it passed through -- capped at 4 distinct collapse
// keys per sender at a time, which only matters if one resident has 5+
// reports all mid-update while their phone is offline, a rare enough
// case that it is not worth engineering around. Notifications with no
// report_id (verification) are untouched -- there is nothing to collapse
// them against, and collapsing unrelated account updates into one another
// would drop information a resident hasn't seen yet.

interface NotificationRecord {
  id: string;
  user_id: string;
  report_id: string | null;
  kind: string;
  message: string;
}

interface WebhookPayload {
  type: string;
  table: string;
  record: NotificationRecord;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const FCM_CLIENT_EMAIL = Deno.env.get("FCM_CLIENT_EMAIL")!;
const FCM_PRIVATE_KEY = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(
  /\\n/g,
  "\n",
);

// Kind -> a short, human title. The body is always notification.message,
// which every function that inserts a notification already writes as a
// complete sentence -- see 0005/0009/0011/0034.
const TITLES: Record<string, string> = {
  assignment: "Dispatch update",
  reroute: "Dispatch update",
  status_change: "Complaint update",
  escalation: "Escalation",
  sla_warning: "SLA warning",
  verification: "Account update",
};

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/// Signs a Google service-account JWT and exchanges it for an OAuth2
/// access token scoped to Firebase Cloud Messaging. Tokens are valid for
/// an hour. A warm function instance serves many notifications in a row
/// (one per row inserted), so the token is kept for 50 minutes rather than
/// minted per call: one RSA signature and one round trip to Google saved
/// on almost every push (0107). A cold instance simply mints a new one.
let cachedToken: { value: string; until: number } | null = null;

async function getAccessToken(): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.until) return cachedToken.value;
  const value = await mintAccessToken();
  cachedToken = { value, until: Date.now() + 50 * 60_000 };
  return value;
}

async function mintAccessToken(): Promise<string> {
  const header = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const nowSeconds = Math.floor(Date.now() / 1000);
  const claims = base64UrlEncode(
    new TextEncoder().encode(
      JSON.stringify({
        iss: FCM_CLIENT_EMAIL,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: nowSeconds,
        exp: nowSeconds + 3600,
      }),
    ),
  );
  const unsigned = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(FCM_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`Google OAuth token exchange failed: ${await res.text()}`);
  }
  const json = await res.json();
  return json.access_token as string;
}

// Mute preferences (migration 0044). Checked here and only here — the
// notifications row itself always gets written by whatever RPC created
// it; this is the one place a push is actually sent, so it's the one
// place that needs to know a resident asked not to be buzzed for this
// kind. Fails open (returns false, i.e. "not muted") on any lookup
// trouble: a fetch hiccup must never silently swallow a real
// notification the recipient didn't ask to have suppressed.
// The notification exactly as the database holds it (security fix, 7 Oct
// 2026). The webhook's own copy is not trusted: anyone signed in can call
// this function, and a made-up payload used to push any text to any
// account. Now only a real, stored notification is ever sent, to its own
// owner; a forged call can at most repeat one.
async function storedNotification(id: unknown): Promise<NotificationRecord | null> {
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/notifications?id=eq.${id}&select=id,user_id,report_id,kind,message`,
    { headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` } },
  );
  if (!res.ok) throw new Error(`could not read notification ${id}: ${res.status}`);
  const rows = (await res.json()) as NotificationRecord[];
  return rows[0] ?? null;
}

async function isKindMuted(userId: string, kind: string): Promise<boolean> {
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/users?id=eq.${userId}&select=muted_notification_kinds`,
      {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      },
    );
    if (!res.ok) return false;
    const rows = (await res.json()) as
      { muted_notification_kinds: string[] | null }[];
    return (rows[0]?.muted_notification_kinds ?? []).includes(kind);
  } catch (e) {
    console.error("Could not check mute preference:", e);
    return false;
  }
}

async function fetchDeviceTokens(userId: string): Promise<string[]> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/device_tokens?user_id=eq.${userId}&select=fcm_token`,
    {
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
    },
  );
  if (!res.ok) {
    console.error("Could not read device_tokens:", await res.text());
    return [];
  }
  const rows = (await res.json()) as { fcm_token: string }[];
  return rows.map((r) => r.fcm_token);
}

async function deleteStaleToken(token: string): Promise<void> {
  try {
    await fetch(
      `${SUPABASE_URL}/rest/v1/device_tokens?fcm_token=eq.${encodeURIComponent(token)}`,
      {
        method: "DELETE",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      },
    );
  } catch (e) {
    console.error("Could not delete stale token:", e);
  }
}

async function sendToToken(
  accessToken: string,
  token: string,
  record: NotificationRecord,
): Promise<void> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: TITLES[record.kind] ?? "SmartSumbong",
            body: record.message,
          },
          data: {
            report_id: record.report_id ?? "",
            kind: record.kind,
            notification_id: record.id,
          },
          android: {
            priority: "high",
            // See the file header: same report id as both the collapse
            // key and the tag, so repeat status pushes for one report
            // replace each other instead of stacking.
            ...(record.report_id
              ? {
                  collapse_key: record.report_id,
                  notification: { tag: record.report_id },
                }
              : {}),
          },
        },
      }),
    },
  );

  if (res.ok) return;

  const body = await res.text();
  // UNREGISTERED / NOT_FOUND: the app was uninstalled or the token
  // rotated out from under us. Self-clean rather than retry forever.
  if (res.status === 404 || body.includes("UNREGISTERED")) {
    console.log("Removing stale device token:", token);
    await deleteStaleToken(token);
    return;
  }
  // A refused access token is not kept for the rest of its 50 minutes.
  if (res.status === 401) cachedToken = null;
  console.error(`FCM send failed for one token (status ${res.status}):`, body);
}

// Optional shared secret (0107). When PUSH_WEBHOOK_SECRET is set, only a
// caller sending it in x-webhook-secret is served; add that header to the
// Database Webhook (Dashboard -> Database -> Webhooks) before setting it,
// or pushes stop. Unset, the function behaves as before.
const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";

function sameSecret(sent: string): boolean {
  if (sent.length !== WEBHOOK_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < sent.length; i++) diff |= sent.charCodeAt(i) ^ WEBHOOK_SECRET.charCodeAt(i);
  return diff === 0;
}

export async function handler(req: Request): Promise<Response> {
  if (WEBHOOK_SECRET && !sameSecret(req.headers.get("x-webhook-secret") ?? "")) {
    return new Response("forbidden", { status: 403 });
  }
  try {
    const payload = (await req.json()) as WebhookPayload;

    if (payload.table !== "notifications" || payload.type !== "INSERT") {
      return new Response("ignored", { status: 200 });
    }

    const record = await storedNotification(payload.record?.id);
    if (!record) {
      return new Response("no such notification", { status: 200 });
    }

    if (await isKindMuted(record.user_id, record.kind)) {
      // Still a real notification -- the row this webhook fired for
      // already exists and already did its job as the in-app record.
      // This only skips the phone buzz the recipient asked not to get.
      return new Response("muted by recipient", { status: 200 });
    }

    const tokens = await fetchDeviceTokens(record.user_id);
    if (tokens.length === 0) {
      // Normal, not an error: most users have not opened a build with
      // push wired in yet, or never granted the notification permission.
      return new Response("no devices registered", { status: 200 });
    }

    const accessToken = await getAccessToken();
    await Promise.all(
      tokens.map((token) => sendToToken(accessToken, token, record)),
    );

    return new Response("sent", { status: 200 });
  } catch (e) {
    // Logged, not thrown: a webhook delivery failure must never look like
    // the notifications insert itself failed. The row already exists and
    // already serves its purpose as the in-app record either way.
    console.error("send-dispatch-push failed:", e);
    return new Response("error, see function logs", { status: 200 });
  }
}
