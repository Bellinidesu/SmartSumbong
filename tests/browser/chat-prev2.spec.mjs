// Local audit tool: CP=1 npx playwright test chat-prev2.spec.mjs -> the right-click menu, a floated head on another page, a new message, the Settings card.
import { test } from '@playwright/test';
test.skip(!process.env.CP, 'audit tool');
test.setTimeout(120000);
const OUT = 'C:/Users/acele/AppData/Local/Temp/claude/f69caae7ff9b002e/ccfb5882-e083-41a8-8f98-f68c68abfe82/scratchpad/cp/';
const CASE = 'case.php?id=c0000000-0000-0000-0000-000000000001';
for (const mode of ['light', 'dark']) test(`chat float ${mode}`, async ({ page, context }) => {
  const errors = []; page.on('pageerror', e => errors.push(String(e)));
  await page.setViewportSize({ width: 1600, height: 1000 }); await page.emulateMedia({ colorScheme: mode });
  await page.goto(CASE); await page.evaluate(m => { try { localStorage.clear(); localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
  await page.reload({ waitUntil: 'networkidle' }); await page.waitForTimeout(600);
  await page.click('#ch-fab', { button: 'right' }); await page.waitForTimeout(250);
  await page.screenshot({ path: `${OUT}float-${mode}-1menu.png`, clip: { x: 1100, y: 600, width: 500, height: 400 } });
  await page.click('.ch-mi:has-text("Float on every page")'); await page.waitForTimeout(300);
  await page.goto('cases.php', { waitUntil: 'networkidle' }); await page.waitForTimeout(1200);
  await page.screenshot({ path: `${OUT}float-${mode}-2cases.png` });
  // the resident writes: the poll sees it
  await page.evaluate(() => fetch('http://127.0.0.1:54399/rest/v1/rpc/fake_incoming', { method: 'POST', body: '{"body":"Kuya, may dumating na po ba?"}' }));
  await page.evaluate(() => window.ssChatPoll()); await page.waitForTimeout(800);
  await page.screenshot({ path: `${OUT}float-${mode}-3new.png`, clip: { x: 1000, y: 700, width: 600, height: 300 } });
  await page.click('.ch-float .ch-fab'); await page.waitForTimeout(900);
  await page.screenshot({ path: `${OUT}float-${mode}-4open.png`, clip: { x: 1100, y: 250, width: 500, height: 750 } });
  await page.keyboard.press('Escape');
  // drag it to the left edge, middle
  const b = await page.locator('.ch-float .ch-fab').boundingBox();
  await page.mouse.move(b.x + 29, b.y + 29); await page.mouse.down(); await page.mouse.move(400, 300, { steps: 8 }); await page.mouse.up(); await page.waitForTimeout(400);
  await page.click('.ch-float .ch-fab'); await page.waitForTimeout(700);
  await page.screenshot({ path: `${OUT}float-${mode}-5dragged.png` });
  await page.goto('settings.php', { waitUntil: 'networkidle' }); await page.click('.st-tabs [data-st="look"]'); await page.waitForTimeout(500);
  await page.locator('#chp').scrollIntoViewIfNeeded(); await page.screenshot({ path: `${OUT}float-${mode}-6settings.png` });
  console.log('ERRORS', JSON.stringify(errors));
});
