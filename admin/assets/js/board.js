// The Notifications work board: drag a card to another stage and the real action opens first. Nothing moves by itself:
// a column a tanod fills says so, and Cancel leaves everything as it was.
(function () {
  var dragging = null, sheet = null;
  window.ssBoardBusy = function () { return !!dragging || !!sheet; };

  function clearOver() { document.querySelectorAll('.bd-col.is-over').forEach(function (c) { c.classList.remove('is-over'); }); }
  function closeSheet() { if (sheet) { sheet.remove(); sheet = null; } }

  document.addEventListener('dragstart', function (e) {
    var c = e.target.closest && e.target.closest('.bd-card'); if (!c) return;
    dragging = c; c.classList.add('is-drag');
    if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; try { e.dataTransfer.setData('text/plain', c.dataset.title || ''); } catch (x) {} }
  });
  document.addEventListener('dragend', function () { if (dragging) dragging.classList.remove('is-drag'); dragging = null; clearOver(); });
  document.addEventListener('dragover', function (e) {
    var col = e.target.closest && e.target.closest('.bd-col'); if (!col || !dragging) return;
    e.preventDefault(); clearOver(); col.classList.add('is-over');
  });
  document.addEventListener('drop', function (e) {
    var col = e.target.closest && e.target.closest('.bd-col'); if (!col || !dragging) return;
    e.preventDefault(); clearOver();
    var card = dragging; dragging = null; card.classList.remove('is-drag');
    if (col === card.closest('.bd-col')) return;
    openSheet(col, card);
  });

  function openSheet(col, card) {
    closeSheet();
    var wrap = document.getElementById('board'), ok = col.dataset.ok === '1';
    var href = card.dataset.href + (ok ? col.dataset.hash || '' : '');
    sheet = document.createElement('div');
    sheet.className = 'bd-sheet'; sheet.setAttribute('role', 'dialog'); sheet.setAttribute('aria-label', col.dataset.verb || col.querySelector('h4').textContent);
    var h = document.createElement('h4'); h.textContent = ok ? col.dataset.verb : col.querySelector('h4').textContent;
    var who = document.createElement('p'); who.className = 'bd-sheet-case'; who.textContent = card.dataset.title || '';
    var hint = document.createElement('p'); hint.textContent = col.dataset.hint || '';
    var row = document.createElement('div'); row.className = 'bd-sheet-row';
    var primary;
    if (ok) {
      primary = document.createElement('a'); primary.className = 'p-btn p-btn-primary p-btn-sm'; primary.href = href; primary.textContent = wrap.dataset.sheetOk;
      var cancel = document.createElement('button'); cancel.type = 'button'; cancel.className = 'p-btn p-btn-ghost p-btn-sm'; cancel.textContent = wrap.dataset.sheetCancel; cancel.addEventListener('click', closeSheet);
      row.appendChild(primary); row.appendChild(cancel);
    } else {
      primary = document.createElement('button'); primary.type = 'button'; primary.className = 'p-btn p-btn-primary p-btn-sm'; primary.textContent = wrap.dataset.sheetClose; primary.addEventListener('click', closeSheet);
      row.appendChild(primary);
    }
    sheet.appendChild(h); sheet.appendChild(who); sheet.appendChild(hint); sheet.appendChild(row);
    document.body.appendChild(sheet);
    primary.focus();
  }
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeSheet(); });
  document.addEventListener('click', function (e) {
    // a card's own menu closes when another part of the page is used
    document.querySelectorAll('.bd-menu[open]').forEach(function (m) { if (!m.contains(e.target)) m.removeAttribute('open'); });
  });
})();
