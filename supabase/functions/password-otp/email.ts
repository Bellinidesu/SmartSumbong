// SmartSumbong — the two emails password-otp sends: a password reset code and an email confirming code (17 Nov 2026).
//
// The look is docs/email/reset-password.html, the administrators' reset email: the same header image served by the portal,
// Inter / Inter Tight, the orange, the amber note and the navy footer with the barangay seal. Inline styles and tables only,
// because email clients drop <style> blocks. Each email also goes as plain text for clients that show no HTML.

const PORTAL = "https://smartsumbong-ph.onrender.com";
const FONT = "'Inter','Segoe UI',Arial,Helvetica,sans-serif";
const TIGHT = "'Inter Tight','Segoe UI',Arial,Helvetica,sans-serif";

export type Purpose = "reset" | "confirm";

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

/** a•••@gmail.com: the first letter and the domain, so the person knows which address without anyone else learning it. */
export function maskEmail(email: string): string {
  const [local, domain] = email.trim().split("@");
  if (!local || !domain) return "•••";
  return `${local.slice(0, 1)}•••@${domain}`;
}

/** 0917•••4567 */
export function maskMobile(mobile: string): string {
  const local = "0" + mobile.replace(/\D/g, "").slice(-10);
  return `${local.slice(0, 4)}•••${local.slice(-4)}`;
}

type Words = { eyebrow: string; title: string; lead: string; leadFil: string; pill: string; note: string; subject: string };

function words(purpose: Purpose, minutes: number, mobile: string, tanod: boolean): Words {
  const account = tanod ? "tanod account" : "SmartSumbong account";
  if (purpose === "reset") {
    return {
      subject: "Your SmartSumbong password reset code",
      eyebrow: "Account security",
      title: "Reset your password",
      lead: `Someone asked to reset the password for the <b style="color:#12172B;font-weight:800;">${account}</b> on ` +
        `<b style="color:#12172B;font-weight:800;">${esc(maskMobile(mobile))}</b>. If that was you, enter this code in the app.`,
      leadFil: "Ilagay ang code na ito sa app para makapili ng bagong password.",
      pill: tanod ? "Tanod account" : "Resident account",
      note: `The code works once and expires after ${minutes} minutes. Didn't ask for this? Ignore this email; your password stays ` +
        "the same. The barangay will never ask you for this code.",
    };
  }
  return {
    subject: "Confirm your email for SmartSumbong",
    eyebrow: "Your email",
    title: "Confirm your email",
    lead: `Enter this code in <b style="color:#12172B;font-weight:800;">Edit Profile</b> to confirm this address for the ` +
      `${account} on <b style="color:#12172B;font-weight:800;">${esc(maskMobile(mobile))}</b>. ` +
      "Once it is confirmed, password reset codes come here.",
    leadFil: "Ilagay ang code na ito sa Edit Profile para makumpirma ang email na ito.",
    pill: tanod ? "Tanod account" : "Resident account",
    note: `The code works once and expires after ${minutes} minutes. Didn't add this email to SmartSumbong? Ignore this email; ` +
      "nothing changes.",
  };
}

// The plain-text copy: entities decoded in one pass (so "&amp;lt;" stays "&lt;"), then tags removed until none are left.
const ENTITY: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" };
const strip = (html: string) => {
  let s = html.replace(/&(amp|lt|gt|quot|#39);/g, (_, e: string) => ENTITY[e]);
  for (let prev = ""; prev !== s;) { prev = s; s = s.replace(/<[^<>]*>?/g, ""); }
  return s.replace(/[<>]/g, "");
};

export function compose(purpose: Purpose, code: string, opts: { minutes: number; mobile: string; tanod: boolean }) {
  const w = words(purpose, opts.minutes, opts.mobile, opts.tanod);
  const spaced = `${code.slice(0, 3)} ${code.slice(3)}`;
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><title>${esc(w.title)}</title>
<link href="https://fonts.googleapis.com/css2?family=Inter+Tight:wght@700;800&family=Inter:wght@500;600;700;800&display=swap" rel="stylesheet"></head>
<body style="margin:0;padding:0;background:#E9EDF6;">
<div style="display:none;max-height:0;overflow:hidden;">${esc(`${w.title}. The code inside expires in ${opts.minutes} minutes.`)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#E9EDF6;padding:28px 12px 36px;font-family:${FONT};">
  <tr><td align="center">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #E6E8EE;box-shadow:0 2px 4px rgba(20,27,52,0.04),0 8px 24px rgba(20,27,52,0.06);">
      <tr><td style="padding:0;line-height:0;">
        <img src="${PORTAL}/admin/assets/img/email-header.jpg" width="520" alt="SmartSumbong · Barangay 183" style="display:block;width:100%;max-width:520px;height:auto;border:0;">
      </td></tr>
      <tr><td style="padding:30px 32px 6px;">
        <div style="font-family:${FONT};font-size:11.5px;font-weight:700;letter-spacing:1px;color:#00308F;text-transform:uppercase;">${esc(w.eyebrow)}</div>
        <div style="font-family:${TIGHT};font-size:26px;line-height:1.2;font-weight:800;color:#12172B;margin:8px 0 12px;">${esc(w.title)}</div>
        <div style="font-family:${FONT};font-size:15.5px;line-height:1.6;color:#4B5468;font-weight:500;">${w.lead}</div>
        <div style="font-family:${FONT};font-size:13.5px;line-height:1.55;color:#6B7280;font-weight:500;margin-top:6px;font-style:italic;">${esc(w.leadFil)}</div>
        <table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:14px;"><tr>
          <td style="padding:0 6px 0 0;"><span style="display:inline-block;font-family:${FONT};font-size:12.5px;font-weight:700;color:#4B5468;background:#ffffff;border:1px solid #DDE1EA;border-radius:99px;padding:5px 12px;">${esc(w.pill)}</span></td>
          <td><span style="display:inline-block;font-family:${FONT};font-size:12.5px;font-weight:700;color:#A36400;background:#FFF1D6;border-radius:99px;padding:5px 12px;">Expires in ${opts.minutes} minutes</span></td>
        </tr></table>
      </td></tr>
      <tr><td align="center" style="padding:24px 32px 10px;">
        <div style="display:inline-block;background:#FFF6E8;border:2px dashed #FF9800;border-radius:14px;padding:14px 26px;font-family:${TIGHT};font-size:34px;line-height:40px;font-weight:800;letter-spacing:8px;color:#12172B;">${esc(spaced)}</div>
        <div style="font-family:${FONT};font-size:12px;font-weight:600;color:#6B7280;margin-top:8px;">Your 6-digit code</div>
      </td></tr>
      <tr><td style="padding:14px 32px 26px;">
        <div style="background:#FFF1D6;color:#A36400;border-radius:12px;padding:12px 16px;font-family:${FONT};font-size:13.5px;font-weight:600;line-height:1.55;">${esc(w.note)}</div>
      </td></tr>
      <tr><td align="center" style="padding:20px 24px 22px;background:#00308F;">
        <table role="presentation" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:99px;"><tr>
          <td style="padding:7px;"><img src="${PORTAL}/admin/assets/img/brgy-183-seal.png" height="34" alt="Barangay 183 seal" style="display:block;border:0;"></td>
        </tr></table>
        <div style="color:#ffffff;font-family:${FONT};font-size:14px;font-weight:800;margin-top:12px;">SmartSumbong · Barangay 183</div>
        <div style="color:#AFC2EE;font-family:${FONT};font-size:11.5px;font-weight:600;margin-top:2px;">Barangay 183, Zone 20, Villamor, Pasay City</div>
      </td></tr>
    </table>
  </td></tr>
</table></body></html>`;
  const text = [
    w.title,
    "",
    strip(w.lead),
    w.leadFil,
    "",
    `Your code: ${spaced}`,
    "",
    strip(w.note),
    "",
    "SmartSumbong · Barangay 183, Zone 20, Villamor, Pasay City",
  ].join("\n");
  return { subject: w.subject, html, text };
}
