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
/// an hour; this function is short-lived enough that minting a fresh one
/// per invocation is simpler and safer than caching one across calls.
async function getAccessToken(): Promise<string> {
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
          android: { priority: "high" },
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
  console.error(`FCM send failed for one token (status ${res.status}):`, body);
}

Deno.serve(async (req: Request) => {
  try {
    const payload = (await req.json()) as WebhookPayload;

    if (payload.table !== "notifications" || payload.type !== "INSERT") {
      return new Response("ignored", { status: 200 });
    }

    const record = payload.record;
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
});
