// Local audit tool: AD2=1 npx playwright test adser-shot.spec.mjs -> Administrative Services: Roles, Retirement requests, Escalation and responders, light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.AD2, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/adx/';
for (const theme of ['light', 'dark']) test('adser ' + theme, async ({ page }) => {
  await page.addInitScript((t) => { try { localStorage.setItem('ss-theme', t); localStorage.setItem('ss-side', 'min'); } catch (e) {} document.addEventListener('DOMContentLoaded', () => { document.documentElement.setAttribute('data-theme', t); document.documentElement.setAttribute('data-side', 'min'); }); }, theme);
  await page.setViewportSize({ width: 2048, height: 1200 });
  await page.goto('administrative-services.php', { waitUntil: 'networkidle' });
  await page.locator('.st-tabs [data-st="admins"]').click(); await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + theme + '-roles.png', clip: { x: 80, y: 0, width: 1968, height: 800 } });
  await page.locator('.ad-roles .cm-chip[data-role="kagawad"]').click(); await page.waitForTimeout(700);
  await page.screenshot({ path: OUT + theme + '-roles2.png', clip: { x: 80, y: 120, width: 1968, height: 420 } });
  await page.locator('.st-tabs [data-st="ladder"]').click(); await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + theme + '-ladder.png', fullPage: true });
  await page.goto('retirement-requests.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + theme + '-retire.png', clip: { x: 80, y: 0, width: 1968, height: 700 } });
});
