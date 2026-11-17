// SmartSumbong — one email over SMTP, with nothing but Deno's own TLS (17 Nov 2026).
//
// password-otp sends its codes from the barangay's Gmail. Supabase's Edge runtime blocks the plain SMTP ports (25, 587), so this
// speaks implicit TLS on 465, the port Gmail keeps for it: TLS from the first byte, then EHLO, AUTH PLAIN with a Gmail app
// password, one message, QUIT. No library: the functions take no third-party code, and one message to one address needs only
// these few commands. Each part of the message is base64 (UTF-8 safe, no line ever starts with a dot) and the subject and
// sender name are RFC 2047 words, so "·" and Tagalog arrive intact.
//
// The connection is a parameter, so the tests can play the server (handler.test.ts) and nothing here ever reaches the network
// from a test.

export type Conn = {
  read(p: Uint8Array): Promise<number | null>;
  write(p: Uint8Array): Promise<number>;
  close(): void;
};
export type Connect = (opts: { hostname: string; port: number }) => Promise<Conn>;

export type Smtp = { host: string; port: number; user: string; pass: string; fromName: string };
export type Mail = { to: string; subject: string; text: string; html: string };

const enc = new TextEncoder();
const dec = new TextDecoder();

/** A plain address: one @, no spaces or line breaks, nothing a header could be split with. */
export function plainAddress(s: string): boolean {
  return s.length <= 254 && /^[^@\s<>()",;:\\]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(s);
}

function b64(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

/** Base64 in 76-character lines, as MIME asks. */
function b64Lines(text: string): string {
  return b64(enc.encode(text)).replace(/.{1,76}/g, "$&\r\n");
}

/** A header word in UTF-8 (RFC 2047), only when it needs it. */
function word(s: string): string {
  return /^[\x20-\x7E]*$/.test(s) ? s : `=?UTF-8?B?${b64(enc.encode(s))}?=`;
}

/** The whole message as it goes after DATA, ending in the lone dot. */
export function message(from: string, fromName: string, mail: Mail, now = new Date()): string {
  const boundary = `ss-${crypto.randomUUID()}`;
  const domain = from.split("@")[1] ?? "localhost";
  const name = fromName.replace(/["\\\r\n]/g, "");
  const head = [
    `From: ${/^[\x20-\x7E]*$/.test(name) ? `"${name}"` : word(name)} <${from}>`,
    `To: <${mail.to}>`,
    `Subject: ${word(mail.subject.replace(/[\r\n]+/g, " "))}`,
    `Date: ${now.toUTCString().replace("GMT", "+0000")}`,
    `Message-ID: <${crypto.randomUUID()}@${domain}>`,
    "MIME-Version: 1.0",
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
  ].join("\r\n");
  const part = (type: string, body: string) =>
    `--${boundary}\r\nContent-Type: ${type}; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${b64Lines(body)}`;
  const body = `${head}\r\n\r\n${part("text/plain", mail.text)}${part("text/html", mail.html)}--${boundary}--\r\n`;
  // Base64 never starts a line with a dot, but the rule is cheap to keep anyway.
  return body.replace(/^\./gm, "..") + ".\r\n";
}

/** Reads whole SMTP replies (the last line of one has a space after its code). */
class Replies {
  private buf = "";
  constructor(private conn: Conn) {}
  async next(): Promise<{ code: number; text: string }> {
    const chunk = new Uint8Array(4096);
    for (;;) {
      const lines = this.buf.split("\r\n");
      for (let i = 0; i < lines.length - 1; i++) {
        if (/^\d{3} /.test(lines[i]) || /^\d{3}$/.test(lines[i])) {
          const text = lines.slice(0, i + 1).join("\n");
          this.buf = lines.slice(i + 1).join("\r\n");
          return { code: Number(lines[i].slice(0, 3)), text };
        }
      }
      if (this.buf.length > 64_000) throw new Error("smtp: reply too long");
      const n = await this.conn.read(chunk);
      if (n === null) throw new Error("smtp: the server closed the connection");
      this.buf += dec.decode(chunk.subarray(0, n), { stream: true });
    }
  }
}

/**
 * Sends one message. Resolves when the server has taken it; throws with the server's reply otherwise (never with the password).
 * Gives up after `timeoutMs` in all.
 */
export async function sendMail(cfg: Smtp, mail: Mail, connect: Connect, timeoutMs = 12_000): Promise<void> {
  if (!plainAddress(mail.to)) throw new Error("smtp: not a plain address");
  if (!plainAddress(cfg.user)) throw new Error("smtp: SMTP_USER is not an address");
  let conn: Conn | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const talk = async () => {
    conn = await connect({ hostname: cfg.host, port: cfg.port });
    const c = conn;
    const replies = new Replies(c);
    const expect = async (what: string, ...ok: number[]) => {
      const r = await replies.next();
      if (!ok.includes(r.code)) throw new Error(`smtp: ${what} refused: ${r.text.replace(/\s+/g, " ").slice(0, 160)}`);
      return r;
    };
    const say = async (line: string) => { await c.write(enc.encode(line + "\r\n")); };
    await expect("greeting", 220);
    await say("EHLO smartsumbong");
    await expect("EHLO", 250);
    await say(`AUTH PLAIN ${b64(enc.encode(`\0${cfg.user}\0${cfg.pass}`))}`);
    await expect("sign-in", 235);
    await say(`MAIL FROM:<${cfg.user}>`);
    await expect("sender", 250);
    await say(`RCPT TO:<${mail.to}>`);
    await expect("recipient", 250, 251);
    await say("DATA");
    await expect("DATA", 354);
    await c.write(enc.encode(message(cfg.user, cfg.fromName, mail)));
    await expect("message", 250);
    await say("QUIT");
    await replies.next().catch(() => undefined);   // a server that hangs up instead of saying 221 has still taken the message
  };
  try {
    await Promise.race([
      talk(),
      new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("smtp: timed out")), timeoutMs); }),
    ]);
  } finally {
    clearTimeout(timer);
    try { (conn as Conn | null)?.close(); } catch { /* already closed */ }
  }
}
