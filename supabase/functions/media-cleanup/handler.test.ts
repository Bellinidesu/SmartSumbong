// deno test --allow-env supabase/functions
import { assertEquals } from "jsr:@std/assert@1.0.19";
import { type Call, json, setEnv, stubFetch } from "../_test/stub.ts";

setEnv({
  SUPABASE_URL: "https://sb.test", SUPABASE_SERVICE_ROLE_KEY: "service-key",
  MEDIA_CLEANUP_SECRET: "cleanup-secret", CLOUDINARY_API_KEY: "key", CLOUDINARY_API_SECRET: "abcd",
});
const { handler, parse, apiSignature } = await import("./handler.ts");

const AVATAR = "https://res.cloudinary.com/nwb2kryl/image/upload/v17/avatars/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11.jpg";
const ID = "https://res.cloudinary.com/nwb2kryl/image/authenticated/v17/ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e12.jpg";
const run = (secret?: string) =>
  new Request("http://localhost/", { method: "POST", headers: secret ? { "x-cleanup-secret": secret } : {}, body: "{}" });

Deno.test("only identity photos parse; evidence never does", () => {
  assertEquals(parse(ID), { cloud: "nwb2kryl", type: "authenticated", publicId: "ids/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e12" });
  assertEquals(parse(AVATAR)?.type, "upload");
  assertEquals(parse(AVATAR.replace("/avatars/", "/reports/")), null);
});

Deno.test("API signature matches Cloudinary's SDK (SHA-256)", async () => {
  assertEquals(
    await apiSignature({ eager: "w_400,h_300,c_pad|w_260,h_200,c_crop", public_id: "sample_image", timestamp: "1315060510" }, "abcd"),
    "cc927e1290f9e3ae4c1a741eda21a4630b4ce80f9ce0bc0296337d25cf40f91e",
  );
});

Deno.test("refused without the shared secret", async () => {
  const s = stubFetch([]);
  try {
    assertEquals((await handler(run())).status, 403);
    assertEquals((await handler(run("wrong"))).status, 403);
    assertEquals(s.calls.length, 0);
  } finally { s.restore(); }
});

Deno.test("deletes what is due and reports back only what is gone", async () => {
  const s = stubFetch([
    (c: Call) => c.url.pathname === "/rest/v1/rpc/media_trash_due" ? json([AVATAR, ID]) : undefined,
    (c: Call) => c.url.pathname === "/v1_1/nwb2kryl/image/destroy"
      ? (new URLSearchParams(c.body).get("type") === "upload" ? json({ result: "ok" }) : json({ error: { message: "boom" } }, 500))
      : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/rpc/media_trash_done" ? json(null) : undefined,
    (c: Call) => c.url.pathname === "/rest/v1/rpc/log_portal_error" ? json(null) : undefined,
  ]);
  try {
    const res = await handler(run("cleanup-secret"));
    assertEquals(await res.json(), { due: 2, deleted: 1 });
    const done = s.calls.find((c) => c.url.pathname.endsWith("media_trash_done"))!;
    assertEquals(JSON.parse(done.body).p_urls, [AVATAR]);
    const destroyed = s.calls.find((c) => c.url.pathname.endsWith("/destroy"))!;
    assertEquals(new URLSearchParams(destroyed.body).get("public_id"), "avatars/0d9c6c1e-5b7a-4c1e-9a52-3f1f2b6d8e11");
    const logged = s.calls.find((c) => c.url.pathname.endsWith("log_portal_error"))!;
    assertEquals(JSON.parse(logged.body).p_source, "function", "the refused delete is logged for the health check");
  } finally { s.restore(); }
});
