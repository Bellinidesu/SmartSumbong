// Local audit tool: CP=1 npx playwright test chat-prev.spec.mjs -> the chat head closed, open on its list, in both conversations, after a send, in dark.
import { test } from '@playwright/test';
test.skip(!process.env.CP, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/cp/';
const CASE = 'case.php?id=c0000000-0000-0000-0000-000000000001';
for (const mode of ['light', 'dark']) test(`chat ${mode}`, async ({ page }) => {
  const errors = []; page.on('pageerror', e => errors.push(String(e))); page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.setViewportSize({ width: 1600, height: 1000 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto(CASE); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(800);
  const box = { x: 1600 - 460, y: 1000 - 760, width: 460, height: 760 };
  await page.screenshot({ path: `${OUT}chat-${mode}-0closed.png` });
  await page.click('#ch-fab'); await page.waitForTimeout(400);
  await page.screenshot({ path: `${OUT}chat-${mode}-1list.png`, clip: box });
  await page.click('.ch-row >> nth=0'); await page.waitForTimeout(300);
  await page.screenshot({ path: `${OUT}chat-${mode}-2conv-a.png`, clip: box });
  await page.click('.ch-conv:not([hidden]) .ch-back'); await page.click('.ch-row >> nth=1'); await page.waitForTimeout(300);
  await page.screenshot({ path: `${OUT}chat-${mode}-3conv-b.png`, clip: box });
  const ta = page.locator('.ch-conv:not([hidden]) textarea');
  await ta.fill('Sige po, ipapadala na namin ang tanod.'); await page.waitForTimeout(200);
  await page.screenshot({ path: `${OUT}chat-${mode}-4typing.png`, clip: box });
  await ta.press('Enter'); await page.waitForTimeout(1200);
  await page.screenshot({ path: `${OUT}chat-${mode}-5sent.png`, clip: box });
  console.log('ERRORS', JSON.stringify(errors));
});
