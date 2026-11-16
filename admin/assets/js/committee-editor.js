/* The committee editor (committee-editor.php, 16 Nov 2026, Ace). The page's sidebar IS the committee's own sidebar and this script keeps it live: the committee's colour (the same hue
   maths as layout.php side_colour_style), its logo or symbol faded behind, its name under the seal. The banner, the case page's Committee row and the Personnel filter chip beside the
   form change with it. The kinds popup is a <dialog>; leaving with changes asks first. No inline handlers (strict CSP). */
(function () {
  'use strict';
  var ce = document.getElementById('ce'), form = document.getElementById('ce-form');
  if (!ce || !form) { return; }
  var root = document.documentElement, I = window.SD_ICONS || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return [].slice.call((r || document).querySelectorAll(s)); };
  var nameEl = $('#ce-name'), shortEl = $('#ce-short'), colourEl = $('#ce-colour'), logoEl = $('#ce-logo'), clearEl = $('#ce-logo-clear'), saveEl = $('#ce-save');
  var kinds = $$('input[name="cats[]"]', form), isNew = ce.dataset.new === '1', def = ($('#ce-banner-n') || {}).textContent || '';
  var D = ce.dataset, hasLogo = !!$('#ce-lgi img'), markUrl = null, submitting = false;

  function draw(svg, name) { svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '2'); svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round'); svg.innerHTML = I[name] || I.other || ''; }
  $$('.cmx-ti', ce).forEach(function (s) { draw(s, s.dataset.ic); });
  function lum(h) { var n = parseInt(h.slice(1), 16), r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255; return (0.299 * r + 0.587 * g + 0.114 * b) / 255; }
  function hs(hex) {
    var r = parseInt(hex.slice(1, 3), 16) / 255, g = parseInt(hex.slice(3, 5), 16) / 255, b = parseInt(hex.slice(5, 7), 16) / 255, mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, l = (mx + mn) / 2, h = 0, s = 0;
    if (d > 0) { s = d / (1 - Math.abs(2 * l - 1)); h = (mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4) * 60; if (h < 0) { h += 360; } }
    return [Math.round(h), Math.round(Math.min(s * 100, 90)), Math.round(Math.min(s * 100, 30))];
  }
  function dark() { var t = root.getAttribute('data-theme'); return t ? t === 'dark' : !!(window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches); }
  function label() { return ((shortEl.value || nameEl.value || '').trim()) || def; }
  function ticked() { return kinds.filter(function (k) { return k.checked; }); }
  function mono(ic) { return 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' + (I[ic] || I.other || '') + '</svg>'); }

  // the sidebar
  function sidebar() {
    var hex = colourEl.value, c = hs(hex), dk = dark(), sat = dk ? c[2] : c[1];
    root.style.setProperty('--p-side-a', 'hsl(' + c[0] + ' ' + sat + '% ' + (dk ? 20 : 28) + '%)');
    root.style.setProperty('--p-side-b', 'hsl(' + c[0] + ' ' + sat + '% ' + (dk ? 11 : 20) + '%)');
    root.style.setProperty('--p-side-glow', hex);
    var first = ticked()[0], mark = null;
    if (markUrl) { mark = 'url("' + markUrl + '")'; }
    else if (!hasLogo || (clearEl && clearEl.checked)) { mark = first ? 'url("' + mono(first.dataset.ic) + '")' : 'none'; }
    if (mark === null) { root.style.removeProperty('--p-side-mark'); } else { root.style.setProperty('--p-side-mark', mark); }
    var com = $('.p-side-com'), lb = label();
    if (com) { com.style.setProperty('--cc', hex); com.style.setProperty('--ci', lum(hex) > 0.6 ? '#141B34' : '#FFFFFF'); com.title = lb; var b = $('b', com); if (b) { b.textContent = lb; } }
    var sh = $('#ce-side-short'); if (sh) { sh.textContent = lb; }
  }

  // the banner, the Committee row and the filter chip
  function previews() {
    var hex = colourEl.value, on = ticked(), cols = on.slice(0, 3).map(function (k) { return k.dataset.c; }), lb = label();
    if (!cols.length) { cols = [hex]; }
    var chip = $('#ce-banner'), sym = $('.cm-sym', chip);
    chip.style.setProperty('--g1', cols[0]); chip.style.setProperty('--g2', cols[1] || cols[0]); chip.style.setProperty('--g3', cols[2] || cols[1] || cols[0]); chip.style.setProperty('--cc', hex);
    chip.style.setProperty('--ct', cols.reduce(function (a, c) { return a + lum(c); }, 0) / cols.length > 0.62 ? '#2B1A00' : '#FFFFFF');
    sym.className = 'cm-sym cm-sym-sd'; sym.innerHTML = '';
    on.slice(0, 3).forEach(function (k) { var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); s.setAttribute('class', 'cm-ic'); s.setAttribute('viewBox', '0 0 24 24'); s.setAttribute('aria-hidden', 'true'); draw(s, k.dataset.ic); sym.appendChild(s); });
    if (on.length > 3) { var m = document.createElement('b'); m.className = 'cm-more'; m.textContent = '+' + (on.length - 3); sym.appendChild(m); }
    var old = $('.cm-bg', chip); if (old) { old.remove(); }
    var f = $('svg', sym); if (f) { var g = f.cloneNode(true); g.setAttribute('class', 'cm-bg'); g.setAttribute('aria-hidden', 'true'); chip.appendChild(g); }
    $('#ce-banner-n').textContent = lb;
    $('#ce-crow-i').style.setProperty('--c', hex); $('#ce-crow-n').textContent = lb;
    $('#ce-chip-i').style.setProperty('--c', hex); $('#ce-chip-n').textContent = lb;
    var lgi = $('#ce-lgi'); if (lgi) { lgi.style.setProperty('--cc', hex); lgi.style.setProperty('--ci', lum(hex) > 0.6 ? '#141B34' : '#FFFFFF'); }
  }

  // what it sees: a line of chips, and the count in the popup
  function kindSummary() {
    var box = $('#ce-ksum'), on = ticked(); box.innerHTML = '';
    if (!on.length) { var p = document.createElement('p'); p.className = 'p-hint'; p.textContent = D.sNone; box.appendChild(p); }
    on.forEach(function (k) {
      var s = document.createElement('span'); s.className = 'cmx-t cmx-t-ro'; s.style.setProperty('--tc', k.dataset.c); s.style.setProperty('--tk', lum(k.dataset.c) > 0.62 ? '#2B1A00' : '#FFFFFF');
      var v = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); v.setAttribute('class', 'cm-ic cmx-ti'); v.setAttribute('viewBox', '0 0 24 24'); v.setAttribute('aria-hidden', 'true'); draw(v, k.dataset.ic);
      var t = document.createElement('span'); t.textContent = k.dataset.name; s.appendChild(v); s.appendChild(t); box.appendChild(s);
    });
    var cnt = $('#ce-kcount'); if (cnt) { cnt.textContent = on.length === 1 ? D.sKind : D.sKinds.replace('%d', on.length); }
  }

  // progress, the Save button, and the leave question
  var initial = new URLSearchParams(new FormData(form)).toString();
  function dirty() { return new URLSearchParams(new FormData(form)).toString() !== initial || !!(logoEl && logoEl.files && logoEl.files.length); }
  function progress() {
    var ok1 = (nameEl.value || '').trim().length >= 3, ok2 = ticked().length > 0, n = (ok1 ? 1 : 0) + (ok2 ? 1 : 0);
    var s1 = $('[data-step="1"]'), s2 = $('[data-step="2"]'); s1.classList.toggle('ok', ok1); s2.classList.toggle('ok', ok2);
    $('#ce-prog').innerHTML = ''; var b = document.createElement('b'); b.textContent = D.sSteps.replace('%d', n); var sm = document.createElement('small'); sm.textContent = ok1 ? D.sOk : D.sNeed;
    var w = document.createElement('div'); w.appendChild(b); w.appendChild(sm); $('#ce-prog').appendChild(w);
    saveEl.disabled = !ok1 || (!isNew && !dirty());
  }
  function refresh() { sidebar(); previews(); kindSummary(); progress(); }

  [nameEl, shortEl].forEach(function (e) { e.addEventListener('input', refresh); });
  kinds.forEach(function (k) { k.addEventListener('change', refresh); });
  form.addEventListener('change', progress); form.addEventListener('input', progress);
  if (clearEl) { clearEl.addEventListener('change', refresh); }
  new MutationObserver(sidebar).observe(root, { attributes: true, attributeFilter: ['data-theme'] });

  // colour: the palette's swatches and the free picker
  function swatches() { $$('.ce-swatch').forEach(function (b) { var on = b.dataset.hex === colourEl.value.toLowerCase(); b.classList.toggle('on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false'); }); }
  $$('.ce-swatch').forEach(function (b) { b.addEventListener('click', function () { if (b.disabled) { return; } colourEl.value = b.dataset.hex; swatches(); refresh(); }); });
  colourEl.addEventListener('input', function () { swatches(); refresh(); });

  // logo: shows at once in its slot and in the sidebar
  if (logoEl) {
    // The picture is decoded and redrawn on a canvas (at most 512 px), and that drawing is what the slot and the sidebar show: the file's own address is never put in the page.
    logoEl.addEventListener('change', function () {
      var f = logoEl.files && logoEl.files[0], msg = $('#ce-logo-msg'), box = $('#ce-lgi'), lt = $('#ce-lgt');
      markUrl = null;
      if (!f) { refresh(); return; }
      function bad() { logoEl.value = ''; if (msg) { msg.textContent = D.sLogoBad; } refresh(); }
      if (!/^image\/(png|jpeg|webp)$/.test(f.type) || f.size > 4 * 1024 * 1024 || !window.createImageBitmap) { bad(); return; }
      createImageBitmap(f).then(function (bmp) {
        var s = Math.min(1, 512 / Math.max(bmp.width, bmp.height, 1)), c = document.createElement('canvas');
        c.width = Math.max(1, Math.round(bmp.width * s)); c.height = Math.max(1, Math.round(bmp.height * s));
        c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height); if (bmp.close) { bmp.close(); }
        markUrl = c.toDataURL('image/png');
        box.innerHTML = ''; var im = document.createElement('img'); im.src = markUrl; im.alt = ''; box.appendChild(im); if (lt) { lt.textContent = lt.dataset.have; }
        if (clearEl) { clearEl.checked = false; }
        refresh();
      }).catch(bad);
    });
  }

  // the kinds popup
  var dlg = $('#ce-kinds'), opener = $('#ce-kinds-open');
  if (dlg && opener) {
    opener.addEventListener('click', function () { if (dlg.showModal) { dlg.showModal(); } else { dlg.setAttribute('open', ''); } });
    $$('[data-ce-close]', dlg).forEach(function (b) { b.addEventListener('click', function () { dlg.close(); opener.focus(); }); });
    dlg.addEventListener('click', function (e) { if (e.target === dlg) { dlg.close(); } });
  }

  // leaving
  var leave = $('#ce-leave');
  $$('[data-ce-leave]').forEach(function (a) {
    a.addEventListener('click', function (e) { if (!dirty() || !leave || !leave.showModal) { submitting = true; return; } e.preventDefault(); leave.showModal(); });
  });
  if (leave) {
    $$('[data-ce-stay]', leave).forEach(function (b) { b.addEventListener('click', function () { leave.close(); }); });
    var go = $('#ce-leave-go'); if (go) { go.addEventListener('click', function () { submitting = true; }); }
  }
  window.addEventListener('beforeunload', function (e) { if (!submitting && dirty()) { e.preventDefault(); e.returnValue = ''; } });
  form.addEventListener('submit', function (e) {
    if (!form.checkValidity()) { e.preventDefault(); form.reportValidity(); return; }
    submitting = true;
  });

  refresh(); swatches();
})();
