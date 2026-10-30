import { test } from '@playwright/test';
const PAGES = ['dashboard.php','cases.php','summary.php','notifications.php','inbox.php','residents.php','personnel.php','settings.php','profile.php','spatial.php'];
test('weigh', async ({ page }) => {
  for (const p of PAGES) {
    let n = 0, bytes = 0, css = 0, js = 0, img = 0, font = 0;
    const onResp = async r => { try { const b = (await r.body()).length; n++; bytes += b; const u = r.url(); if (/\.css/.test(u)) css += b; else if (/\.js/.test(u)) js += b; else if (/\.(webp|png|jpg|svg)/.test(u)) img += b; else if (/woff/.test(u)) font += b; } catch {} };
    page.on('response', onResp);
    const t0 = Date.now();
    const r = await page.goto(p, { waitUntil: 'networkidle' }).catch(e => null);
    const dt = Date.now() - t0;
    page.off('response', onResp);
    console.log(`${p.padEnd(18)} ${r ? r.status() : 'ERR'} reqs=${String(n).padStart(3)} total=${Math.round(bytes/1024)}KB css=${Math.round(css/1024)} js=${Math.round(js/1024)} img=${Math.round(img/1024)} font=${Math.round(font/1024)} ${dt}ms`);
  }
});
