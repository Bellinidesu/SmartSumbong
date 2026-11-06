// A picture editor in the portal's own look: the picture sits under a frame, you drag it into place and zoom, and what is inside the frame is what is saved.
//   ssCrop.open({ file | url, round: true|false, aspect: 1 | 12, outW: 640, outH: 640, title: 'Your photo', apply: 'Use this', cancel: 'Cancel' })
//     -> Promise<Blob | null>      (null when cancelled)
// Used for the profile photo (a circle, saved square) and the banner (a wide strip).
(function () {
  if (window.ssCrop) return;
  var lang = (document.documentElement.lang || 'en').slice(0, 2) === 'fi' ? 'fil' : 'en';
  var TXT = lang === 'en'
    ? { zoom: 'Zoom', drag: 'Drag the picture to place it, scroll or use the slider to zoom.', fail: 'This picture could not be opened here. Choose it again from your device.', busy: 'Working…' }
    : { zoom: 'I-zoom', drag: 'Hilahin ang larawan para ilagay, mag-scroll o gamitin ang slider para i-zoom.', fail: 'Hindi mabuksan dito ang larawang ito. Piliin itong muli mula sa iyong device.', busy: 'Ginagawa…' };

  function open(o) {
    return new Promise(function (resolve) {
      var round = !!o.round, aspect = o.aspect || 1, outW = o.outW || 640, outH = o.outH || Math.round(outW / aspect);
      var scrim = document.createElement('div'); scrim.className = 'cr-scrim';
      scrim.innerHTML =
        '<div class="cr-modal" role="dialog" aria-modal="true" aria-labelledby="cr-t">' +
        '<header class="cr-head"><h3 id="cr-t"></h3><button type="button" class="cr-x" aria-label="Close"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg></button></header>' +
        '<div class="cr-stage"><img class="cr-img" alt="" draggable="false"><div class="cr-frame' + (round ? ' is-round' : '') + '"></div><p class="cr-err" hidden></p></div>' +
        '<div class="cr-zoom"><span></span><button type="button" class="cr-z" data-d="-1" aria-label="-">&minus;</button><input type="range" class="cr-range" min="0" max="100" value="0" step="0.5"><button type="button" class="cr-z" data-d="1" aria-label="+">+</button></div>' +
        '<p class="cr-hint"></p>' +
        '<div class="cr-actions"><button type="button" class="p-btn p-btn-ghost cr-cancel"></button><button type="button" class="p-btn p-btn-primary cr-ok"></button></div></div>';
      var $ = function (s) { return scrim.querySelector(s); };
      $('#cr-t').textContent = o.title || '';
      $('.cr-zoom span').textContent = TXT.zoom; $('.cr-hint').textContent = TXT.drag;
      $('.cr-cancel').textContent = o.cancel || 'Cancel'; $('.cr-ok').textContent = o.apply || 'Use this';
      document.body.appendChild(scrim); document.documentElement.classList.add('cr-open');
      var stage = $('.cr-stage'), img = $('.cr-img'), frame = $('.cr-frame'), range = $('.cr-range'), ok = $('.cr-ok'), err = $('.cr-err');
      var objUrl = null, W = 0, H = 0, fw = 0, fh = 0, fx = 0, fy = 0, iw = 0, ih = 0, s0 = 1, k = 1, cx = 0, cy = 0, ready = false;
      function layout() {
        W = stage.clientWidth; H = stage.clientHeight;
        fw = round ? Math.min(W, H) * 0.78 : W * 0.9; fh = fw / aspect;
        if (fh > H * 0.84) { fh = H * 0.84; fw = fh * aspect; }
        fx = (W - fw) / 2; fy = (H - fh) / 2;
        frame.style.cssText = 'left:' + fx + 'px;top:' + fy + 'px;width:' + fw + 'px;height:' + fh + 'px';
      }
      function sc() { return s0 * k; }
      function clamp() {
        var s = sc(), halfW = iw * s / 2, halfH = ih * s / 2;
        cx = Math.min(fx + halfW, Math.max(fx + fw - halfW, cx)); cy = Math.min(fy + halfH, Math.max(fy + fh - halfH, cy));
      }
      function paint() { clamp(); var s = sc(); img.style.cssText = 'width:' + iw + 'px;height:' + ih + 'px;transform:translate(' + (cx - iw / 2) + 'px,' + (cy - ih / 2) + 'px) scale(' + s + ')'; }
      function setK(nk, ax, ay) {   // zoom around a point of the stage
        nk = Math.max(1, Math.min(5, nk)); var s = sc(), ns = s0 * nk;
        ax = ax == null ? W / 2 : ax; ay = ay == null ? H / 2 : ay;
        cx = ax - (ax - cx) * ns / s; cy = ay - (ay - cy) * ns / s; k = nk; range.value = (k - 1) / 4 * 100; paint();
      }
      function close(blob) { document.removeEventListener('keydown', onKey, true); window.removeEventListener('resize', onResize); scrim.classList.remove('in'); setTimeout(function () { scrim.remove(); document.documentElement.classList.remove('cr-open'); if (objUrl) URL.revokeObjectURL(objUrl); }, 200); resolve(blob); }
      function onKey(e) { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(null); } }
      function onResize() { if (!ready) return; var rx = (cx - fx) / fw, ry = (cy - fy) / fh; layout(); s0 = Math.max(fw / iw, fh / ih); cx = fx + rx * fw; cy = fy + ry * fh; setK(k); }
      img.onload = function () {
        iw = img.naturalWidth; ih = img.naturalHeight; layout(); s0 = Math.max(fw / iw, fh / ih); k = 1; cx = W / 2; cy = H / 2; ready = true; paint(); ok.disabled = false;
      };
      img.onerror = function () { err.textContent = TXT.fail; err.hidden = false; ok.disabled = true; };
      ok.disabled = true;
      if (o.file) { objUrl = URL.createObjectURL(o.file); img.src = objUrl; } else { img.crossOrigin = 'anonymous'; img.src = o.url; }
      // drag to place; two fingers or the wheel to zoom
      var ptrs = {}, last = null;
      stage.addEventListener('pointerdown', function (e) { if (!ready) return; stage.setPointerCapture(e.pointerId); ptrs[e.pointerId] = { x: e.clientX, y: e.clientY }; last = null; stage.classList.add('is-drag'); });
      stage.addEventListener('pointermove', function (e) {
        var p = ptrs[e.pointerId]; if (!p) return; var ids = Object.keys(ptrs);
        if (ids.length === 2) {
          var a = ptrs[ids[0]], b = ptrs[ids[1]]; if (ids[0] == e.pointerId) { a = { x: e.clientX, y: e.clientY }; } else { b = { x: e.clientX, y: e.clientY }; }
          var d = Math.hypot(a.x - b.x, a.y - b.y); if (last) { var r = stage.getBoundingClientRect(); setK(k * d / last, (a.x + b.x) / 2 - r.left, (a.y + b.y) / 2 - r.top); } last = d;
        } else { cx += e.clientX - p.x; cy += e.clientY - p.y; paint(); }
        p.x = e.clientX; p.y = e.clientY;
      });
      function up(e) { delete ptrs[e.pointerId]; last = null; if (!Object.keys(ptrs).length) stage.classList.remove('is-drag'); }
      stage.addEventListener('pointerup', up); stage.addEventListener('pointercancel', up);
      stage.addEventListener('wheel', function (e) { if (!ready) return; e.preventDefault(); var r = stage.getBoundingClientRect(); setK(k * (e.deltaY < 0 ? 1.08 : 1 / 1.08), e.clientX - r.left, e.clientY - r.top); }, { passive: false });
      range.addEventListener('input', function () { if (ready) setK(1 + range.value / 100 * 4); });
      scrim.querySelectorAll('.cr-z').forEach(function (b) { b.addEventListener('click', function () { if (ready) setK(k + Number(b.dataset.d) * 0.25); }); });
      $('.cr-x').addEventListener('click', function () { close(null); }); $('.cr-cancel').addEventListener('click', function () { close(null); });
      scrim.addEventListener('pointerdown', function (e) { if (e.target === scrim) close(null); });
      document.addEventListener('keydown', onKey, true); window.addEventListener('resize', onResize);
      ok.addEventListener('click', function () {
        if (!ready) return; ok.disabled = true; ok.textContent = TXT.busy;
        var s = sc(), sx = (fx - (cx - iw * s / 2)) / s, sy = (fy - (cy - ih * s / 2)) / s, sw = fw / s, sh = fh / s;
        var c = document.createElement('canvas'); c.width = outW; c.height = outH; var g = c.getContext('2d');
        g.imageSmoothingQuality = 'high'; g.fillStyle = '#fff'; g.fillRect(0, 0, outW, outH);
        try { g.drawImage(img, sx, sy, sw, sh, 0, 0, outW, outH); c.toBlob(function (b) { if (b) close(b); else { err.textContent = TXT.fail; err.hidden = false; ok.disabled = false; ok.textContent = o.apply || 'Use this'; } }, 'image/jpeg', 0.92); }
        catch (x) { err.textContent = TXT.fail; err.hidden = false; ok.disabled = false; ok.textContent = o.apply || 'Use this'; }
      });
      requestAnimationFrame(function () { scrim.classList.add('in'); $('.cr-ok').focus({ preventScroll: true }); });
    });
  }
  window.ssCrop = { open: open };
})();
