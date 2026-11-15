// Local audit tool: GM=1 npx playwright test gmail-shot.spec.mjs -> BarangayMail (Gmail-style): the list, a conversation, a compose window, in light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.GM, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/gm/';
for (const mode of ['light', 'dark']) test(`gmail ${mode}`, async ({ page }) => {
  const errors = []; page.on('pageerror', e => errors.push('PAGE ' + e.message)); page.on('console', m => { if (m.type() === 'error' && !/WebSocket|realtime/i.test(m.text())) errors.push('CONSOLE ' + m.text()); });
  await page.setViewportSize({ width: 1700, height: 1000 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('inbox.php?app=mail'); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(900);
  await page.screenshot({ path: `${OUT}gm-${mode}-1list.png` });
  await page.locator('.gm-row').first().hover(); await page.waitForTimeout(300);
  await page.screenshot({ path: `${OUT}gm-${mode}-2hover.png`, clip: { x: 256, y: 190, width: 1440, height: 260 } });
  await page.locator('.gm-row .gm-subj').first().click(); await page.waitForTimeout(900);
  await page.screenshot({ path: `${OUT}gm-${mode}-3thread.png` });
  await page.click('[data-gm="reply"]'); await page.waitForTimeout(700);
  await page.screenshot({ path: `${OUT}gm-${mode}-4reply.png` });
  await page.goto('inbox.php?app=mail#inbox'); await page.waitForTimeout(600);
  await page.click('[data-gm="compose"]'); await page.waitForTimeout(700);
  await page.screenshot({ path: `${OUT}gm-${mode}-5compose.png` });
  console.log('ERRORS', JSON.stringify(errors));
});
