// deno test --allow-env supabase/functions
import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { b64u, encrypt, importP256, unb64u, vapid } from "./webpush.ts";

// RFC 8291, section 5: the worked example, byte for byte.
Deno.test("encryption matches RFC 8291's example", async () => {
  const asPublic = unb64u("BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8");
  const asPrivate = await importP256(unb64u("yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw"), asPublic, "ECDH");
  const body = await encrypt(
    new TextEncoder().encode("When I grow up, I want to be a watermelon"),
    unb64u("BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"),
    unb64u("BTBZMqHH6r4Tts7J_aSIgg"),
    { asPrivate, asPublic, salt: unb64u("DGv6ra1nlYgDCS1FRnbzlw") },
  );
  assertEquals(b64u(body),
    "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_" +
    "yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN");
});

Deno.test("the VAPID token is ES256, for the push service's origin, and verifies", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pub = b64u(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  const h = await vapid("https://fcm.googleapis.com/fcm/send/abc", "mailto:test@example.org", pub, pair.privateKey);
  const m = h.match(/^vapid t=([^.]+)\.([^.]+)\.([^,]+), k=(.+)$/)!;
  assert(m, h);
  assertEquals(JSON.parse(new TextDecoder().decode(unb64u(m[1]))).alg, "ES256");
  const claims = JSON.parse(new TextDecoder().decode(unb64u(m[2])));
  assertEquals(claims.aud, "https://fcm.googleapis.com");
  assert(claims.exp > Date.now() / 1000);
  assertEquals(m[4], pub);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, unb64u(m[3]),
    new TextEncoder().encode(`${m[1]}.${m[2]}`));
  assert(ok, "signature verifies");
});
