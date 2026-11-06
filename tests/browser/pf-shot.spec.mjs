// Local audit tool: PF2=1 npx playwright test pf-shot.spec.mjs -> Profile and Edit Profile, the picture editor and the colour picker, light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.PF2, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/pfx/';
for (const theme of ['light', 'dark']) test('profile ' + theme, async ({ page }) => {
  await page.addInitScript((t) => { try { localStorage.setItem('ss-theme', t); localStorage.setItem('ss-side', 'min'); } catch (e) {} document.addEventListener('DOMContentLoaded', () => { document.documentElement.setAttribute('data-theme', t); document.documentElement.setAttribute('data-side', 'min'); }); }, theme);
  await page.setViewportSize({ width: 2048, height: 1100 });
  await page.goto('profile.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(600);
  await page.screenshot({ path: OUT + theme + '-view.png', clip: { x: 80, y: 0, width: 1968, height: 800 } });
  await page.goto('profile.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(600); await page.locator('.ss-pf-head').hover(); await page.waitForTimeout(400);
  await page.screenshot({ path: OUT + theme + '-edit.png', clip: { x: 80, y: 0, width: 1968, height: 800 } });
  await page.locator('.pf-avbtn').click(); await page.waitForTimeout(500);
  await page.screenshot({ path: OUT + theme + '-m-avatar.png' });
  const png = await page.evaluate(() => { const c = document.createElement('canvas'); c.width = 900; c.height = 600; const g = c.getContext('2d'); const gr = g.createLinearGradient(0, 0, 900, 600); gr.addColorStop(0, '#ff9800'); gr.addColorStop(1, '#356cf9'); g.fillStyle = gr; g.fillRect(0, 0, 900, 600); return c.toDataURL('image/png').split(',')[1]; });
  await page.setInputFiles('#avatar', { name: 'a.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await page.waitForSelector('.cr-modal'); await page.waitForTimeout(400);
  await page.screenshot({ path: OUT + theme + '-crop-photo.png' });
  await page.locator('.cr-ok').click(); await page.waitForTimeout(400);
  await page.locator('#m-avatar [data-pf-cancel]').click(); await page.waitForTimeout(300);
  await page.goto('profile.php', { waitUntil: 'networkidle' }); await page.locator('.ss-pf-head').hover(); await page.locator('.pf-cvbtn').click(); await page.waitForTimeout(500);
  await page.screenshot({ path: OUT + theme + '-m-cover.png' });
  await page.locator('#m-cover .sdp-colour').click(); await page.waitForTimeout(400);
  await page.screenshot({ path: OUT + theme + '-colour.png' });
  await page.keyboard.press('Escape'); await page.keyboard.press('Escape');
  await page.goto('profile.php?edit=1', { waitUntil: 'networkidle' }); await page.waitForTimeout(500);
  await page.screenshot({ path: OUT + theme + '-m-details.png' });
});
