// Lighthouse (Apache-2.0) on four portal pages, run in Playwright's own Chromium against the test site (serve.sh).
// Accessibility must stay at 95 or more and best practices at 90 or more; performance under 80 only warns, because CI
// machines vary. The full reports are written to lighthouse/ (a CI artifact). Run: node lighthouse.mjs
import fs from 'node:fs';
import lighthouse from 'lighthouse';
import desktop from 'lighthouse/core/config/desktop-config.js';
import * as chromeLauncher from 'chrome-launcher';
import { chromium } from '@playwright/test';

const BASE = 'http://127.0.0.1:8013/admin/';
const PAGES = ['login.php', 'dashboard.php', 'cases.php', 'summary.php'];
const BARS = { accessibility: [95, 'fail'], 'best-practices': [90, 'fail'], performance: [80, 'warn'] };

fs.mkdirSync('lighthouse', { recursive: true });
const chrome = await chromeLauncher.launch({ chromePath: chromium.executablePath(), chromeFlags: ['--headless=new', '--no-sandbox'] });
let failed = false;
try {
  for (const page of PAGES) {
    const { lhr, report } = await lighthouse(BASE + page, { port: chrome.port, output: 'html', logLevel: 'error' }, desktop);
    fs.writeFileSync(`lighthouse/${page.replace('.php', '')}.html`, report);
    const line = [];
    for (const [cat, [min, kind]] of Object.entries(BARS)) {
      const score = Math.round((lhr.categories[cat]?.score ?? 0) * 100);
      const low = score < min;
      if (low && kind === 'fail') failed = true;
      line.push(`${cat} ${score}${low ? (kind === 'fail' ? ` FAIL (under ${min})` : ` (warning: under ${min})`) : ''}`);
    }
    console.log(`${page.padEnd(15)} ${line.join(', ')}`);
  }
} finally {
  await chrome.kill();
}
process.exit(failed ? 1 : 0);
