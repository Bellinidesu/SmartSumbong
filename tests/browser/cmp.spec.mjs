// Local audit tool: CMP=out.json npx playwright test cmp.spec.mjs -> a hash of every element's computed style, per page and theme.
import { test } from '@playwright/test';
import fs from 'node:fs'; import crypto from 'node:crypto';
test.skip(!process.env.CMP, 'audit tool');
const CASE = 'c0000000-0000-0000-0000-000000000001';
const PAGES = ['dashboard.php', 'cases.php', `case.php?id=${CASE}`, 'summary.php', 'spatial.php', 'notifications.php', 'inbox.php', 'residents.php', 'personnel.php', 'settings.php', 'profile.php', 'activity.php', 'administrative-services.php', 'control-room.php', 'workspace.php', 'login.php'];
const res = {};
test.setTimeout(240000);
test('cmp', async ({ page }) => {
  for (const mode of ['light', 'dark']) for (const p of PAGES) {
    await page.emulateMedia({ colorScheme: mode, reducedMotion: 'reduce' });
    await page.goto(p); await page.evaluate(m => { try { localStorage.setItem('ss-theme', m); } catch (e) {} }, mode);
    await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(2500);
    await page.addStyleTag({ content: '*,*::before,*::after{animation:none!important;transition:none!important}' }); await page.waitForTimeout(300);
    res[`${mode} ${p}`] = await page.evaluate(() => {
      const out = []; const els = [...document.querySelectorAll('body *')].slice(0, 2500);
      for (const el of els) {
        if (el.closest('canvas, .maplibregl-canvas-container')) continue;
        const cs = getComputedStyle(el); let s = '';
        for (const k of ['display','position','color','background-color','background-image','border-top-color','border-radius','box-shadow','opacity','width','height','margin-top','padding-top','font-size','font-weight','backdrop-filter','transform','z-index','top','left','right','bottom','filter']) s += cs.getPropertyValue(k) + '|';
        out.push((el.tagName + '.' + (el.className && el.className.baseVal === undefined ? el.className : '') + '#' + el.id).slice(0, 80) + ' ' + s);
      }
      return out;
    });
  }
  fs.writeFileSync(process.env.CMP, JSON.stringify(res));
});
