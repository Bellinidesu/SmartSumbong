// Local audit tool: CP=1 npx playwright test inbox-chats-shot.spec.mjs -> the Inbox's Case chats (Messenger-style), light and dark, and a phone.
import { test } from '@playwright/test';
test.skip(!process.env.CP, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/cp/';
for (const mode of ['light', 'dark']) test(`messenger ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: 1700, height: 1000 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('inbox.php'); await page.evaluate(m => { try { Object.keys(localStorage).filter(k => k.startsWith('ss-chat-') || k.startsWith('ss-msgr')).forEach(k => localStorage.removeItem(k)); localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(600);
  await page.screenshot({ path: `${OUT}mg-${mode}-1empty.png` });
  await page.click('[data-mg-row]:has-text("Garcia")'); await page.waitForTimeout(900);
  await page.screenshot({ path: `${OUT}mg-${mode}-2open.png` });
  await page.fill('.mg-center textarea', 'Sige po, nandiyan na ang tanod'); await page.click('.mg-emoji'); await page.waitForTimeout(400);
  await page.screenshot({ path: `${OUT}mg-${mode}-3emoji.png` });
});
test('messenger phone', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 800 });
  await page.goto('inbox.php'); await page.waitForLoadState('networkidle'); await page.waitForTimeout(500);
  await page.screenshot({ path: `${OUT}mg-phone-1list.png` });
  await page.click('[data-mg-row]:has-text("Lediac")'); await page.waitForTimeout(800);
  await page.screenshot({ path: `${OUT}mg-phone-2conv.png` });
});
