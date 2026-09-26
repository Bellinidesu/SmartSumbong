<?php
/**
 * Portal language (branch B): English or Tagalog, the same pair the
 * resident and tanod apps offer. Strings are written in place as
 * t('English', 'Tagalog') — the apps' i18n.dart does the same with
 * _t(en, fil) — so a screen's two versions sit side by side and cannot
 * drift apart the way a separate dictionary file does.
 *
 * The choice is a cookie (ss-lang), set by the switch in the sidebar and
 * on the sign-in page, so it reaches the server on the very first
 * request and the page is rendered in that language — not flashed in
 * English and then rewritten.
 *
 * The signed PDF of Report Summary stays in English: it is the
 * barangay's official record, whatever the screen is set to.
 */
declare(strict_types=1);

const LANG_COOKIE = 'ss-lang';

function lang(): string
{
    if (isset($GLOBALS['ss_lang_force'])) { return $GLOBALS['ss_lang_force']; }
    static $l = null;
    return $l ??= (($_COOKIE[LANG_COOKIE] ?? '') === 'fil' ? 'fil' : 'en');
}

/** Pick the string for the current language. */
function t(string $en, string $fil): string
{
    return lang() === 'fil' ? $fil : $en;
}

/**
 * Pin the language for the rest of the request, whatever the cookie
 * says — the official PDF, which stays English.
 */
function force_lang(string $l): void
{
    $GLOBALS['ss_lang_force'] = $l === 'fil' ? 'fil' : 'en';
}

/** "September 2026" / "Setyembre 2026". */
function month_year(DateTimeInterface $d): string
{
    return month_name((int) $d->format('n')) . ' ' . $d->format('Y');
}

function month_name(int $n): string
{
    if (lang() !== 'fil') {
        return date('F', mktime(0, 0, 0, $n, 1));
    }
    return ['Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo', 'Hulyo',
            'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre'][$n - 1];
}

/** The html lang attribute value. */
function html_lang(): string
{
    return lang() === 'fil' ? 'fil' : 'en';
}

/**
 * The script every page puts first in <head> (branch B): the language for
 * page scripts (T(en, fil), mirroring t() above), and the theme — the
 * saved choice, or the device's own setting until one is made — applied
 * before anything paints, so a dark-mode visit never flashes white.
 */
function theme_head(): string
{
    return '<script>'
        . 'window.LANG=' . json_encode(lang()) . ';'
        . 'window.T=function(en,fil){return window.LANG==="fil"?fil:en;};'
        . '(function(){var t=null;try{t=localStorage.getItem("ss-theme");}catch(e){}'
        . 'if(t!=="light"&&t!=="dark"){t=window.matchMedia&&matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light";}'
        . 'document.documentElement.setAttribute("data-theme",t);'
        . 'document.documentElement.setAttribute("data-bs-theme",t);})();'
        // Screen fit (branch B): the design is drawn at 1440 wide, so on a
        // bigger screen the whole portal is scaled up rather than stretched
        // thin — 1080p and 1440p then look alike, as the Figma frame does.
        // The zoom is the smaller of width/1440 and height/810 (so a short
        // window never has to scroll just to reach the sidebar), never
        // below 1 and at most 1.8. --z lets CSS viewport units undo it.
        . '(function(){var d=document.documentElement;function fit(){'
        . 'var z=Math.min(innerWidth/1440,innerHeight/810,1.8);if(!(z>1))z=1;z=Math.round(z*1000)/1000;'
        . 'd.style.zoom=z;d.style.setProperty("--z",z);'
        . 'var h=innerHeight/z;if(h<900)d.setAttribute("data-short","");else d.removeAttribute("data-short");'
        . 'if(h<780)d.setAttribute("data-tight","");else d.removeAttribute("data-tight");}'
        . 'fit();addEventListener("resize",fit);})();'
        . '</script>';
}

/**
 * The theme and language switches (sidebar, sign-in page). Theme is
 * stored in the browser; language in the ss-lang cookie, then the page
 * reloads so the server renders it in the new language.
 */
function prefs_switches(string $extraClass = ''): string
{
    $en  = lang() === 'en';
    $moon = '<svg class="pref-ic pref-ic--moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
          . 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>';
    $sun  = '<svg class="pref-ic pref-ic--sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
          . 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4.5"/>'
          . '<path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
    ob_start(); ?>
<div class="prefs <?= e($extraClass) ?>">
  <button type="button" class="pref-theme" data-theme-toggle
          data-dark="<?= e(t('Dark mode', 'Madilim na anyo')) ?>" data-light="<?= e(t('Light mode', 'Maliwanag na anyo')) ?>">
    <?= $moon . $sun ?><span data-theme-label><?= e(t('Dark mode', 'Madilim na anyo')) ?></span>
  </button>
  <div class="pref-lang" role="group" aria-label="<?= e(t('Language', 'Wika')) ?>">
    <button type="button" data-lang="en" aria-pressed="<?= $en ? 'true' : 'false' ?>">English</button>
    <button type="button" data-lang="fil" aria-pressed="<?= $en ? 'false' : 'true' ?>">Tagalog</button>
  </div>
</div>
<script>
(function () {
  var root = document.documentElement;
  function label() {
    document.querySelectorAll('[data-theme-toggle]').forEach(function (b) {
      var dark = root.getAttribute('data-theme') === 'dark';
      b.querySelector('[data-theme-label]').textContent = dark ? b.dataset.light : b.dataset.dark;
      b.setAttribute('aria-pressed', dark ? 'true' : 'false');
    });
  }
  document.querySelectorAll('[data-theme-toggle]').forEach(function (b) {
    if (b.dataset.bound) return; b.dataset.bound = '1';
    b.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      root.setAttribute('data-bs-theme', next);
      try { localStorage.setItem('ss-theme', next); } catch (e) {}
      label();
      window.dispatchEvent(new CustomEvent('themechange', { detail: next }));
    });
  });
  document.querySelectorAll('.pref-lang [data-lang]').forEach(function (b) {
    if (b.dataset.bound) return; b.dataset.bound = '1';
    b.addEventListener('click', function () {
      if (b.getAttribute('aria-pressed') === 'true') return;
      document.cookie = 'ss-lang=' + b.dataset.lang + '; path=/; max-age=31536000; samesite=lax';
      location.reload();
    });
  });
  label();
})();
</script>
<?php
    return (string) ob_get_clean();
}
