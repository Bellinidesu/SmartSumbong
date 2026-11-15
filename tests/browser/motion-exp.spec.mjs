import { test } from '@playwright/test';
test.skip(!process.env.MO, 'tool');
test('exp', async ({ page }) => {
  test.setTimeout(200000);
  const cdp = await page.context().newCDPSession(page); await cdp.send('Performance.enable');
  const get = async () => Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]));
  const variants = { default: '', none: '*,*::before,*::after{animation:none!important}',
    noRing: '.ss-brain-btn{animation:none!important}', noBeat: '.ss-brain-btn .ss-brain-ico{animation:none!important}', noFlow: '.ss-brain-btn .ss-brain-ico path{animation:none!important}',
    onlyRing: '.ss-brain-btn .ss-brain-ico, .ss-brain-btn .ss-brain-ico path{animation:none!important}' };
  for (const p of ['cases.php']) for (const [k, css] of Object.entries(variants)) {
    await page.goto(p, { waitUntil: 'domcontentloaded' }); if (css) await page.addStyleTag({ content: css }); await page.waitForTimeout(2500);
    const a = await get(); await page.waitForTimeout(6000); const b = await get(); const s = b.Timestamp - a.Timestamp;
    console.log(p.padEnd(14), k.padEnd(12), 'task', (100 * (b.TaskDuration - a.TaskDuration) / s).toFixed(1) + '%', 'style', (100 * (b.RecalcStyleDuration - a.RecalcStyleDuration) / s).toFixed(1) + '%');
  }
});
