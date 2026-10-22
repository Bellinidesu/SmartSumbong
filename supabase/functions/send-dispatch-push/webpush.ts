// SmartSumbong — Web Push for the portal's browsers (0136)
//
// Written against the two standards with the Web Crypto API alone, the way
// handler.ts already signs its own Google token, so no library rides along:
//   RFC 8291  the message is encrypted for the one browser that asked for it
//             (ECDH on P-256, HKDF, AES-128-GCM in the aes128gcm format of
//             RFC 8188). The push service passes it on and cannot read it.
//   RFC 8292  VAPID: a short ES256-signed token says the push comes from us.
// webpush.test.ts checks the encryption against RFC 8291's own example.
//
// Keys (`supabase secrets set`): VAPID_PUBLIC_KEY (65-byte uncompressed
// point) and VAPID_PRIVATE_KEY (32-byte scalar), both base64url; the portal
// hands the public one to browsers. VAPID_SUBJECT is a mailto: or https:
// address a push service can reach us at.

const enc = new TextEncoder();
// Bytes over a plain ArrayBuffer, which is what Web Crypto and fetch take.
type Bytes = Uint8Array<ArrayBuffer>;

export function b64u(bytes: Bytes): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function unb64u(s: string): Bytes {
  const b = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4));
  return Uint8Array.from(b, (c) => c.charCodeAt(0));
}

function concat(...parts: Uint8Array[]): Bytes {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

async function hkdf(salt: Bytes, ikm: Bytes, info: Bytes, bytes: number): Promise<Bytes> {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, key, bytes * 8));
}

/// A P-256 private key from its raw scalar and public point (Web Crypto takes them only as a JWK).
export function importP256(d: Bytes, pub: Bytes, alg: "ECDH" | "ECDSA"): Promise<CryptoKey> {
  const jwk = { kty: "EC", crv: "P-256", d: b64u(d), x: b64u(pub.slice(1, 33)), y: b64u(pub.slice(33, 65)), ext: true };
  return crypto.subtle.importKey("jwk", jwk, { name: alg, namedCurve: "P-256" }, false, alg === "ECDH" ? ["deriveBits"] : ["sign"]);
}

/// RFC 8291: the body a push service carries to one browser. `fixed` is only
/// for the test against the RFC's example; a real push gets a fresh key and salt.
export async function encrypt(
  plaintext: Bytes, uaPublic: Bytes, authSecret: Bytes,
  fixed?: { asPrivate: CryptoKey; asPublic: Bytes; salt: Bytes },
): Promise<Bytes> {
  let asPrivate: CryptoKey, asPublic: Bytes;
  if (fixed) {
    ({ asPrivate, asPublic } = fixed);
  } else {
    const pair = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
    asPrivate = pair.privateKey;
    asPublic = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  }
  const uaKey = await crypto.subtle.importKey("raw", uaPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, asPrivate, 256));
  const ikm = await hkdf(authSecret, shared, concat(enc.encode("WebPush: info\0"), uaPublic, asPublic), 32);
  const salt = fixed?.salt ?? crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, enc.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, enc.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  // one record, ended by the 0x02 delimiter
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, concat(plaintext, new Uint8Array([2]))));
  // header: salt, record size 4096, then the key id (our public key)
  const head = new Uint8Array(21);
  head.set(salt);
  new DataView(head.buffer).setUint32(16, 4096);
  head[20] = asPublic.length;
  return concat(head, asPublic, sealed);
}

/// RFC 8292: the Authorization header for one push service, good for 12 hours.
export async function vapid(endpoint: string, subject: string, publicKey: string, privateKey: CryptoKey): Promise<string> {
  const part = (o: unknown) => b64u(enc.encode(JSON.stringify(o)));
  const unsigned = part({ typ: "JWT", alg: "ES256" }) + "." +
    part({ aud: new URL(endpoint).origin, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject });
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privateKey, enc.encode(unsigned)));
  return `vapid t=${unsigned}.${b64u(sig)}, k=${publicKey}`;
}

// The browsers' own push services; 0136 holds the table to the same list.
const SERVICES = /^https:\/\/(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9.-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)\//;

export interface Browser { id: number; endpoint: string; p256dh: string; auth: string }

/// Sends one push. `gone` means the browser turned alerts off or forgot us:
/// the caller removes that row.
export async function sendWebPush(
  to: Browser, payload: unknown,
  opts: { subject: string; publicKey: string; privateKey: CryptoKey; urgent?: boolean; topic?: string },
): Promise<{ ok: boolean; gone: boolean; status: number }> {
  if (!SERVICES.test(to.endpoint)) return { ok: false, gone: true, status: 0 };
  const body = await encrypt(enc.encode(JSON.stringify(payload)), unb64u(to.p256dh), unb64u(to.auth));
  const headers: Record<string, string> = {
    Authorization: await vapid(to.endpoint, opts.subject, opts.publicKey, opts.privateKey),
    "Content-Encoding": "aes128gcm",
    "Content-Type": "application/octet-stream",
    TTL: String(24 * 3600),
    Urgency: opts.urgent ? "high" : "normal",
  };
  // A newer push for the same case replaces one still waiting (a report id without dashes is 32 characters, the limit).
  if (opts.topic) headers.Topic = opts.topic.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 32);
  const res = await fetch(to.endpoint, { method: "POST", headers, body });
  await res.body?.cancel();
  return { ok: res.ok, gone: res.status === 404 || res.status === 410, status: res.status };
}
