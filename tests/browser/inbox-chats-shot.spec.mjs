// Local audit tool: CP=1 npx playwright test inbox-chats-shot.spec.mjs -> the Inbox's Case chats folder, light and dark.
import { test } from '@playwright/test';
test.skip(!process.env.CP, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/cp/';
for (const mode of ['light', 'dark']) test(`inbox chats ${mode}`, async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto('inbox.php?box=chats'); await page.evaluate(m => { try { Object.keys(localStorage).filter(k => k.startsWith('ss-chat-')).forEach(k => localStorage.removeItem(k)); localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(700);
  await page.screenshot({ path: `${OUT}inbox-${mode}-1list.png` });
  await page.click('[data-chat-row]'); await page.waitForTimeout(900);
  await page.screenshot({ path: `${OUT}inbox-${mode}-2pane.png` });
  await page.click('.ch-inline .ch-row >> nth=0'); await page.waitForTimeout(500);
  await page.screenshot({ path: `${OUT}inbox-${mode}-3conv.png` });
});
