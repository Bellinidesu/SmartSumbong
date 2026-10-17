// The Notifications work board, as close to Trello as the barangay's rules allow.
// Click a card: a panel opens beside the board with why the engine ranks it and what you can do. Drag a card to a stage:
// the same panel opens on that stage's action. Assigning a tanod and passing a case up finish right there (the same checks
// as the case page, one handler per case); every other stage opens the case. A card only moves once the server agrees,
// and a column only a tanod can fill says so.
(function () {
  var wrap = function () { return document.getElementById('board'); };
  var L = function () { try { return JSON.parse(wrap().dataset.i18n || '{}'); } catch (e) { return {}; } };
  var dragging = null, panel = null, ghost = null, current = null;
  window.ssBoardBusy = function () { return !!dragging || !!panel; };

  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; }
  function clearOver() {
    document.querySelectorAll('.bd-col.is-over').forEach(function (c) { c.classList.remove('is-over'); });
    if (ghost) { ghost.remove(); ghost = null; }
  }

  // ---- drag and drop
  document.addEventListener('dragstart', function (e) {
    var c = e.target.closest && e.target.closest('.bd-card'); if (!c) return;
    dragging = c;
    if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; try { e.dataTransfer.setData('text/plain', c.dataset.title || ''); } catch (x) {} }
    setTimeout(function () { if (dragging) dragging.classList.add('is-drag'); }, 0);
  });
  document.addEventListener('dragend', function () { if (dragging) dragging.classList.remove('is-drag'); dragging = null; clearOver(); });
  document.addEventListener('dragover', function (e) {
    var col = e.target.closest && e.target.closest('.bd-col'); if (!col || !dragging) return;
    e.preventDefault();
    if (!col.classList.contains('is-over')) {
      clearOver(); col.classList.add('is-over');
      if (col !== dragging.closest('.bd-col')) {
        ghost = el('div', 'bd-ghost' + (col.dataset.ok === '1' ? '' : ' is-no'), col.dataset.ok === '1' ? (L().drop || '') : (L().noDrop || ''));
        col.querySelector('.bd-list').prepend(ghost);
      }
    }
  });
  document.addEventListener('drop', function (e) {
    var col = e.target.closest && e.target.closest('.bd-col'); if (!col || !dragging) return;
    e.preventDefault();
    var card = dragging; dragging = null; card.classList.remove('is-drag'); clearOver();
    if (col === card.closest('.bd-col')) return;
    openPanel(card, col);
  });
  document.addEventListener('click', function (e) {
    document.querySelectorAll('.bd-menu[open]').forEach(function (m) { if (!m.contains(e.target)) m.removeAttribute('open'); });
    var card = e.target.closest && e.target.closest('.bd-card');
    if (!card || e.target.closest('.bd-menu') || e.metaKey || e.ctrlKey || e.shiftKey || e.button) return;
    if (e.target.closest('a')) e.preventDefault();      // the title is a real link for middle-click; a plain click opens the panel
    openPanel(card, null);
  });

  // ---- the panel
  function closePanel() { if (panel) { panel.remove(); panel = null; current = null; } document.querySelectorAll('.bd-card.is-open').forEach(function (c) { c.classList.remove('is-open'); }); }
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closePanel(); });

  function openPanel(card, col) {
    closePanel();
    var T = L(), id = card.dataset.id, stage = col ? col.dataset.stage : card.closest('.bd-col').dataset.stage;
    current = { card: card, col: col, id: id };
    card.classList.add('is-open');
    panel = el('aside', 'bd-panel'); panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-label', card.dataset.title || '');
    var head = el('div', 'bd-ph'); var x = el('button', 'bd-x', '×'); x.type = 'button'; x.setAttribute('aria-label', T.close || 'Close'); x.addEventListener('click', closePanel);
    head.appendChild(el('span', 'bd-ptag', card.querySelector('.bd-lv') ? card.querySelector('.bd-lv').textContent : ''));
    head.appendChild(el('span', 'bd-pstage', (card.closest('.bd-col').querySelector('h4') || {}).textContent || ''));
    head.appendChild(x); panel.appendChild(head);
    var body = el('div', 'bd-pb'); panel.appendChild(body);
    body.appendChild(el('p', 'bd-pid', card.dataset.title || ''));
    body.appendChild(el('h3', 'bd-pt', (card.querySelector('.bd-title b') || {}).textContent || ''));
    body.appendChild(el('p', 'bd-pc', (card.querySelector('.bd-cat') || {}).textContent || ''));
    var slot = el('div', 'bd-slot'); slot.appendChild(el('p', 'bd-loading', T.loading || '…')); body.appendChild(slot);
    var foot = el('div', 'bd-pf'); var open = el('a', 'p-btn p-btn-ghost p-btn-sm', T.openCase || 'Open the case'); open.href = card.dataset.href; foot.appendChild(open); panel.appendChild(foot);
    document.body.appendChild(panel);
    fetch(wrap().dataset.act + '?id=' + encodeURIComponent(id), { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) { if (!panel || current.id !== id) return; slot.textContent = ''; if (!res.ok) { slot.appendChild(el('p', 'bd-err', res.j.error || '')); return; } fill(slot, res.j, stage, col, card); })
      .catch(function () { if (panel && current.id === id) { slot.textContent = ''; slot.appendChild(el('p', 'bd-err', T.offline || '')); } });
  }

  function fill(slot, d, stage, col, card) {
    var T = L();
    // who has it, and why the engine ranks it where it does
    var own = el('div', 'bd-pown');
    own.appendChild(el('span', 'bd-pown-l', T.handler || 'Handler'));
    own.appendChild(el('b', '', d.handler ? d.handler.name + (d.mine ? ' (' + (T.you || 'you') + ')' : '') : (T.nobody || 'Nobody yet')));
    slot.appendChild(own);
    if (d.reasons && d.reasons.length) {
      slot.appendChild(el('p', 'bd-eb', T.why || 'Why'));
      var ul = el('ul', 'bd-reasons');
      d.reasons.forEach(function (r) { var li = el('li'); li.appendChild(el('span', '', r.t)); li.appendChild(el('b', '', '+' + r.p)); ul.appendChild(li); });
      slot.appendChild(ul);
    }
    var locked = col && col.dataset.ok !== '1';
    if (locked) { slot.appendChild(el('p', 'bd-note', col.dataset.hint)); return; }
    if (!d.open) { slot.appendChild(el('p', 'bd-note', T.closed || '')); return; }
    if (!d.canAct) { slot.appendChild(el('p', 'bd-note bd-lock', (T.heldBy || '').replace('%s', d.handler ? d.handler.name.split(' ')[0] : ''))); return; }
    var mode = col ? col.dataset.stage : null;
    if (mode === 'dispatch' || (!col && stage === 'dispatch')) { form(slot, d, 'dispatch', col, card); return; }
    if (mode === 'escalation' || (!col && stage === 'escalation')) { form(slot, d, 'escalate', col, card); return; }
    if (col) slot.appendChild(el('p', 'bd-note', col.dataset.hint));
    // a click with no drop: the stage's own quick action when there is one
    if (!col && stage === 'review') slot.appendChild(el('p', 'bd-note', T.reviewHint || ''));
    var q = el('div', 'bd-qa');
    if (d.tier < 2) { var b1 = el('button', 'p-btn p-btn-ghost p-btn-sm', T.passUp || 'Pass it up'); b1.type = 'button'; b1.addEventListener('click', function () { slot.textContent = ''; fill(slot, d, 'escalation', { dataset: { ok: '1', stage: 'escalation', hint: '' } }, card); }); q.appendChild(b1); }
    var b2 = el('button', 'p-btn p-btn-ghost p-btn-sm', T.assign || 'Assign a tanod'); b2.type = 'button'; b2.addEventListener('click', function () { slot.textContent = ''; fill(slot, d, 'dispatch', { dataset: { ok: '1', stage: 'dispatch', hint: '' } }, card); });
    q.appendChild(b2); slot.appendChild(q);
  }

  function field(label, input, id) { var w = el('div', 'bd-f'); var l = el('label', '', label); l.htmlFor = id; input.id = id; w.appendChild(l); w.appendChild(input); return w; }

  function form(slot, d, kind, col, card) {
    var T = L(), f = el('form', 'bd-form'); f.noValidate = false;
    var err = el('p', 'bd-err'); err.hidden = true;
    if (kind === 'dispatch') {
      var list = el('div', 'bd-tan'); var rec = false;
      d.roster.forEach(function (t, i) {
        var lab = el('label', 'bd-tr' + (t.live ? '' : ' is-off'));
        var r = el('input'); r.type = 'radio'; r.name = 'tanod'; r.value = t.id; r.disabled = !t.live; if (t.live && !rec) { r.checked = true; }
        lab.appendChild(r);
        var nm = el('span', 'bd-tn'); nm.appendChild(el('b', '', t.name));
        nm.appendChild(el('small', '', t.live ? (t.metres != null ? t.metres + ' ' + (T.metresAway || 'm away') : '') : (T.notLive || 'Not reporting') + (t.why ? ' · ' + t.why : '')));
        lab.appendChild(nm);
        if (t.live && !rec) { lab.appendChild(el('span', 'bd-rec', T.recommended || 'Recommended')); rec = true; }
        list.appendChild(lab);
      });
      if (!d.roster.length) list.appendChild(el('p', 'bd-note', T.noTanods || ''));
      f.appendChild(el('p', 'bd-eb', T.chooseTanod || 'Choose a tanod')); f.appendChild(list);
      var note = el('textarea'); note.name = 'note'; note.rows = 3; note.required = true; note.maxLength = 500; note.placeholder = T.notePh || '';
      f.appendChild(field(T.instructions || 'Instructions', note, 'bd-note'));
      var tg = el('input'); tg.type = 'datetime-local'; tg.name = 'target'; tg.required = true; tg.value = d.due || '';
      f.appendChild(field(T.target || 'Target date', tg, 'bd-target'));
    } else {
      if (d.tier >= 2) { slot.appendChild(el('p', 'bd-note', T.withChair || '')); return; }
      if (d.tier === 0) {
        var sel = el('select'); sel.name = 'committee';
        var o0 = el('option', '', d.sensitive ? (T.womenFamily || 'Women and Family') + ' (' + (T.sensitive || 'sensitive') + ')' : (T.usualCommittee || 'The usual one for this complaint')); o0.value = ''; sel.appendChild(o0);
        Object.keys(d.committees).forEach(function (k) { var o = el('option', '', d.committees[k]); o.value = k; if (k === d.defaultCommittee && !d.sensitive) { /* the first option already means this one */ } sel.appendChild(o); });
        f.appendChild(field(T.committee || 'Committee', sel, 'bd-comm'));
      }
      var why = el('input'); why.type = 'text'; why.name = 'reason'; why.required = true; why.minLength = 3; why.maxLength = 300; why.placeholder = T.reasonPh || '';
      f.appendChild(field(d.tier === 0 ? (T.reasonK || 'Why (the Kagawad and the resident see it)') : (T.reasonC || 'Why (the Chairman and the resident see it)'), why, 'bd-why'));
      f.appendChild(el('p', 'bd-hint', T.standDown || ''));
    }
    f.appendChild(err);
    var row = el('div', 'bd-prow'); var go = el('button', 'p-btn p-btn-primary p-btn-sm', kind === 'dispatch' ? (T.dispatch || 'Dispatch') : (T.passUp || 'Pass it up')); go.type = 'submit';
    var cancel = el('button', 'p-btn p-btn-ghost p-btn-sm', T.cancel || 'Cancel'); cancel.type = 'button'; cancel.addEventListener('click', closePanel);
    row.appendChild(go); row.appendChild(cancel); f.appendChild(row);
    f.addEventListener('submit', function (e) {
      e.preventDefault(); err.hidden = true; go.disabled = true; go.textContent = T.working || '…';
      var fd = new FormData(f); fd.append('action', kind); fd.append('id', d.id); fd.append('v', d.version); fd.append('csrf', wrap().dataset.csrf);
      fetch(wrap().dataset.act, { method: 'POST', body: fd, credentials: 'same-origin' })
        .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
        .then(function (res) {
          if (!res.ok) { err.textContent = res.j.error || ''; err.hidden = false; go.disabled = false; go.textContent = kind === 'dispatch' ? (T.dispatch || 'Dispatch') : (T.passUp || 'Pass it up'); if (res.j.stale && window.ssBoardRefresh) { closePanelSoon(0); window.ssBoardRefresh(); } return; }
          settle(card, kind === 'dispatch' ? 'accept' : 'escalation', res.j.message, slot);
        })
        .catch(function () { err.textContent = T.offline || ''; err.hidden = false; go.disabled = false; });
    });
    slot.appendChild(f);
    var first = f.querySelector('textarea,input[type=text],select'); if (first) first.focus();
  }

  function closePanelSoon(ms) { setTimeout(closePanel, ms); }

  // the server agreed: the card glides into its new column, then the board is made true from the server
  function settle(card, stage, message, slot) {
    slot.textContent = ''; slot.appendChild(el('p', 'bd-done', '✓ ' + message));
    var target = document.querySelector('.bd-col[data-stage="' + stage + '"] .bd-list');
    if (target && card.isConnected) {
      var from = card.getBoundingClientRect();
      var none = target.querySelector('.bd-none'); if (none) none.remove();
      target.prepend(card);
      var to = card.getBoundingClientRect();
      if (card.animate) card.animate([{ transform: 'translate(' + (from.left - to.left) + 'px,' + (from.top - to.top) + 'px) scale(1.04) rotate(2deg)', boxShadow: '0 18px 36px rgba(0,0,0,.35)' }, { transform: 'none', boxShadow: 'none' }], { duration: 480, easing: 'cubic-bezier(.2,.9,.3,1.1)' });
    }
    setTimeout(function () { closePanel(); if (window.ssBoardRefresh) window.ssBoardRefresh(); }, 1500);
  }
})();
