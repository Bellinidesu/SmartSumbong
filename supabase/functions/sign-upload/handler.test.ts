// deno test --allow-env supabase/functions
import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1.0.19";
import { type Call, json, post, setEnv, stubFetch } from "../_test/stub.ts";

setEnv({
  SUPABASE_URL: "https://sb.test",
  SUPABASE_SERVICE_ROLE_KEY: "service-key",
  CLOUDINARY_API_KEY: "key",
  CLOUDINARY_API_SECRET: "abcd",
});
const { handler, sign, signedView } = await import("./handler.ts");

const ID = "https://res.cloudinary.com/nwb2kryl/image/authenticated/v17/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg";
const PEOPLE: Record<string, { id: string; role: string }> = {
  "res-token": { id: "u-res", role: "resident" },
  "tan-token": { id: "u-tan", role: "tanod" },
  "adm-token": { id: "u-adm", role: "admin" },
};

/** Supabase as each test needs it: who a token is, whose ID is whose, the upload ration. */
function supabase(opts: { slot?: boolean; owns?: string } = {}) {
  return stubFetch([
    (c: Call) => {
      if (c.url.pathname !== "/auth/v1/user") return;
      const who = PEOPLE[(c.headers.get("Authorization") ?? "").replace("Bearer ", "")];
      return who ? json({ id: who.id }) : json({ msg: "invalid JWT" }, 401);
    },
    (c: Call) => {
      if (c.url.pathname !== "/rest/v1/users") return;
      const id = c.url.searchParams.get("id")?.replace("eq.", "");
      if (c.url.searchParams.get("select") === "id") return json(opts.owns === id ? [{ id }] : []);
      const who = Object.values(PEOPLE).find((p) => p.id === id);
      return json(who ? [{ role: who.role, is_suspended: false, is_retired: false }] : []);
    },
    (c: Call) => c.url.pathname === "/rest/v1/profile_requests" ? json([]) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/rpc/take_rate_slot" ? json(opts.slot ?? true) : undefined,
  ]);
}

const as = (token: string) => ({ Authorization: `Bearer ${token}` });

Deno.test("upload signature matches Cloudinary's SDK (SHA-256)", async () => {
  Deno.env.set("CLOUDINARY_API_SECRET", "abcd");
  assertEquals(
    await sign({ eager: "w_400,h_300,c_pad|w_260,h_200,c_crop", public_id: "sample_image", timestamp: "1315060510" }),
    // cloudinary@2.5.1 api_sign_request(..., "abcd") with signature_algorithm "sha256"
    "cc927e1290f9e3ae4c1a741eda21a4630b4ce80f9ce0bc0296337d25cf40f91e",
  );
});

Deno.test("viewing link matches Cloudinary's own SDK", async () => {
  // cloudinary@2.5.1, signature_algorithm "sha256": url(id, {type: "authenticated", sign_url: true, version: 17}), secret "abcd"
  assertEquals(
    await signedView(ID),
    "https://res.cloudinary.com/nwb2kryl/image/authenticated/s--6FzBtDs2--/v17/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg",
  );
});

Deno.test("a resident gets a signature for complaint evidence, named by the function", async () => {
  const s = supabase();
  try {
    const res = await handler(post({ folder: "reports" }, as("res-token")));
    assertEquals(res.status, 200);
    const { fields } = await res.json();
    assertMatch(fields.public_id, /^reports\/[0-9a-f-]{36}$/);
    assertEquals(fields.transformation, "c_limit,w_1920,q_auto");
    assertEquals(fields.type, undefined);
    const { api_key: _k, signature, ...signed } = fields;
    assertEquals(signature, await sign(signed));
  } finally { s.restore(); }
});

Deno.test("a tanod cannot write to complaint evidence, a resident not to field proof", async () => {
  const s = supabase();
  try {
    assertEquals((await handler(post({ folder: "reports" }, as("tan-token")))).status, 403);
    assertEquals((await handler(post({ folder: "dispatch" }, as("res-token")))).status, 403);
    assertEquals((await handler(post({ folder: "dispatch" }, as("tan-token")))).status, 200);
  } finally { s.restore(); }
});

Deno.test("signed out, only registration photos, privately stored and rationed per address", async () => {
  const s = supabase();
  try {
    assertEquals((await handler(post({ folder: "reports" }))).status, 403);
    const res = await handler(post({ folder: "ids" }, { "cf-connecting-ip": "203.0.113.5" }));
    assertEquals(res.status, 200);
    assertEquals((await res.json()).fields.type, "authenticated");
    const slot = s.calls.find((c) => c.url.pathname.endsWith("take_rate_slot"))!;
    assertEquals(JSON.parse(slot.body).p_bucket, "upload-ids:203.0.113.5");
  } finally { s.restore(); }
});

Deno.test("past the ration, registration photos are refused", async () => {
  const s = supabase({ slot: false });
  try {
    assertEquals((await handler(post({ folder: "selfies" }))).status, 429);
  } finally { s.restore(); }
});

Deno.test("profile pictures are public; video only for evidence", async () => {
  const s = supabase();
  try {
    const res = await handler(post({ folder: "avatars" }, as("res-token")));
    assertEquals((await res.json()).fields.type, undefined);
    assertEquals((await handler(post({ folder: "ids", video: true }, as("res-token")))).status, 400);
    assertEquals((await handler(post({ folder: "nowhere" }, as("res-token")))).status, 400);
  } finally { s.restore(); }
});

Deno.test("a private ID opens only for its owner or an administrator", async () => {
  let s = supabase();
  try {
    assertEquals((await handler(post({ view: ID }, as("res-token")))).status, 403);
    assertEquals((await handler(post({ view: ID }))).status, 403);
    const admin = await handler(post({ view: ID }, as("adm-token")));
    assertEquals(admin.status, 200);
    assert((await admin.json()).url.includes("/s--6FzBtDs2--/"));
  } finally { s.restore(); }
  s = supabase({ owns: "u-res" });
  try {
    assertEquals((await handler(post({ view: ID }, as("res-token")))).status, 200);
    const evidence = ID.replace("/ids/", "/reports/");
    assertEquals((await handler(post({ view: evidence }, as("adm-token")))).status, 403);
  } finally { s.restore(); }
});
