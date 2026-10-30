import { test } from '@playwright/test';
const PAGES = ['dashboard.php','cases.php','summary.php','notifications.php','inbox.php','residents.php','personnel.php','settings.php','profile.php','activity.php','accounts.php','case.php','admin-services.php','alerts.php','login.php'];
const SHARED = [[1,70],[170,211],[371,391],[1533,1632]];
const inShared = l => SHARED.some(([a,b]) => l >= a && l <= b);
test('cov2', async ({ page }) => {
  for (const p of PAGES) {
    await page.coverage.startCSSCoverage();
    await page.goto(p, { waitUntil: 'networkidle' }).catch(() => {});
    const cov = await page.coverage.stopCSSCoverage();
    const e = cov.find(c => /flair\.css/.test(c.url)); if (!e) { console.log(p, 'no flair'); continue; }
    const starts = [0]; for (let i = 0; i < e.text.length; i++) if (e.text[i] === '\n') starts.push(i + 1);
    const lineOf = o => { let lo = 0, hi = starts.length - 1; while (lo < hi) { const m = (lo + hi + 1) >> 1; if (starts[m] <= o) lo = m; else hi = m - 1; } return lo + 1; };
    const lines = new Set(); for (const r of e.ranges) for (let o = r.start; o < r.end; o += 1) lines.add(lineOf(o));
    const out = [...lines].filter(l => !inShared(l)).sort((a, b) => a - b);
    console.log('PAGE', p, 'non-shared used lines:', out.length ? out.join(',') : 'none');
  }
});
