/* BarangayMail compose (12 Nov 2026): floating windows with Cc / Bcc chips and people to pick from, formatting marks, the case to attach,
   drafts that save as you type, Undo send, and the reply that sits in the conversation. gmail.js hands in what it shares and gets back the
   doors it opens by. Strict CSP: no inline handlers. */
(function () {
  'use strict';
  window.GMC = function (X) {
    var ME = X.ME, S = X.S, el = X.el, get = X.get, go = X.go, hideSnack = X.hideSnack, ic = X.ic, loadList = X.loadList, openThread = X.openThread, post = X.post,
        readerEl = X.readerEl, snack = X.snack, tr = X.tr, $ = X.$, $$ = X.$$;
    var sugN = 0;
  /* ---------- compose: floating windows, and the reply that sits in the conversation ---------- */
  var wins = [], people = null, peoplePromise = null;
  function loadPeople() { if (people) { return Promise.resolve(people); } if (!peoplePromise) { peoplePromise = get({ v: 'people' }).then(function (j) { people = j.ok ? j.people : []; return people; }); } return peoplePromise; }
  function personById(id) { return (people || []).filter(function (p) { return p.id === id; })[0]; }
  function quoteOf(rp) {
    var d = new Date(rp.quote.at), when = d.toLocaleString(undefined, { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });
    return '\n\n' + tr('On ', 'Noong ') + when + ', ' + rp.quote.who + ' ' + tr('wrote:', 'ay sumulat:') + '\n' + String(rp.quote.body).split(/\r?\n/).map(function (l) { return '> ' + l; }).join('\n');
  }
  function composeFrom(kind) {
    var t = S.thread; if (!t) { return; }
    var rp = t.reply, subj = rp.subject, c = { to: [], cc: [], bcc: [], subject: '', body: '', caseNo: rp.report || '', replyTo: kind === 'forward' ? null : rp.reply_to };
    if (kind === 'forward') { c.subject = /^fwd:/i.test(subj) ? subj : 'Fwd: ' + subj; c.body = '\n\n---------- ' + tr('Forwarded message', 'Ipinasa na mensahe') + ' ----------\n' + tr('From: ', 'Mula kay: ') + rp.quote.who + '\n' + String(rp.quote.body).split(/\r?\n/).map(function (l) { return '> ' + l; }).join('\n'); }
    else {
      c.subject = /^re:/i.test(subj) ? subj : 'Re: ' + subj; c.body = quoteOf(rp);
      var fromMe = rp.mine;
      if (fromMe) { (rp.people || []).forEach(function (p) { if (p.id !== ME && p.role === 'to') { c.to.push({ id: p.id, name: p.name }); } }); }
      else { c.to.push({ id: rp.from.id, name: rp.from.name }); }
      if (kind === 'replyall') { (rp.people || []).forEach(function (p) { if (p.id !== ME && p.role !== 'bcc' && !c.to.some(function (x) { return x.id === p.id; }) && !c.cc.some(function (x) { return x.id === p.id; })) { (p.role === 'cc' ? c.cc : c.to).push({ id: p.id, name: p.name }); } }); }
    }
    newCompose(c, { inline: kind !== 'forward' });
  }
  function openDraft(id) {
    get({ v: 'draft', id: id }).then(function (j) {
      if (!j.ok) { snack(tr('That draft is gone.', 'Wala na ang draft na iyan.')); loadList(true); return; }
      loadPeople().then(function () {
        var d = j.draft, names = function (ids) { return (ids || []).map(function (i) { var p = personById(i); return { id: i, name: p ? p.name : '?' }; }); };
        newCompose({ draftId: d.id, to: names(d.to_ids), cc: names(d.cc_ids), bcc: names(d.bcc_ids), subject: d.subject || '', body: d.body || '', caseNo: d.report && d.report.tracking_id || '', replyTo: d.reply_to || null }, {});
      });
    });
  }

  function newCompose(init, opts) {
    init = init || {}; opts = opts || {};
    if (!opts.inline && wins.length >= 3) { snack(tr('Close a window to start another message.', 'Magsara ng window para makapagsimula ng isa pa.')); return; }
    loadPeople();
    var W = { to: (init.to || []).slice(), cc: (init.cc || []).slice(), bcc: (init.bcc || []).slice(), subject: init.subject || '', body: init.body || '', caseNo: init.caseNo || '', replyTo: init.replyTo || null, draftId: init.draftId || null, inline: !!opts.inline, timer: null, saved: '', sending: false, dirtyAt: 0 };
    var box = el('div', 'gm-win' + (W.inline ? ' gm-win--inline' : '')); box.setAttribute('role', 'dialog'); box.setAttribute('aria-label', tr('New message', 'Bagong mensahe'));
    var head = el('div', 'gm-w-head'), title = el('span', 'gm-w-t', W.inline ? '' : (W.replyTo ? init.subject : tr('New message', 'Bagong mensahe')));
    head.appendChild(title);
    function hbtn(icon, label, fn) { var b = el('button', 'gm-w-b'); b.type = 'button'; b.innerHTML = ic(icon, 16); b.title = label; b.setAttribute('aria-label', label); b.addEventListener('click', function (e) { e.stopPropagation(); fn(); }); head.appendChild(b); return b; }
    var form = el('div', 'gm-w-form');
    function rowOf(label, fieldKey) {
      var r = el('div', 'gm-w-r'), lb = el('span', 'gm-w-l', label), chips = el('span', 'gm-chips'), inp = el('input', 'gm-w-in'); inp.type = 'text'; inp.setAttribute('aria-label', label); inp.autocomplete = 'off'; inp.setAttribute('role', 'combobox'); inp.setAttribute('aria-expanded', 'false');
      var list = el('div', 'gm-sug'); list.setAttribute('role', 'listbox'); list.setAttribute('aria-label', label); list.id = 'gm-sug-' + fieldKey + '-' + (++sugN); inp.setAttribute('aria-controls', list.id); inp.setAttribute('aria-autocomplete', 'list'); list.hidden = true;
      r.appendChild(lb); r.appendChild(chips); r.appendChild(inp); r.appendChild(list);
      function paint() { chips.textContent = ''; W[fieldKey].forEach(function (p) { var c = el('span', 'gm-rc', p.name), x = el('button', '', '✕'); x.type = 'button'; x.setAttribute('aria-label', tr('Remove ', 'Alisin si ') + p.name); x.addEventListener('click', function () { W[fieldKey] = W[fieldKey].filter(function (y) { return y.id !== p.id; }); paint(); changed(); }); c.appendChild(x); chips.appendChild(c); }); }
      function add(p) { if (!W.to.concat(W.cc, W.bcc).some(function (y) { return y.id === p.id; }) && p.id !== ME) { W[fieldKey].push({ id: p.id, name: p.name }); } inp.value = ''; list.hidden = true; inp.setAttribute('aria-expanded', 'false'); paint(); changed(); }
      function suggest() {
        var q = inp.value.trim().toLowerCase(); list.textContent = '';
        if (!q) { list.hidden = true; inp.setAttribute('aria-expanded', 'false'); return; }
        var used = W.to.concat(W.cc, W.bcc).map(function (p) { return p.id; });
        var hit = (people || []).filter(function (p) { return used.indexOf(p.id) < 0 && (p.name + ' ' + p.committee + ' ' + p.role).toLowerCase().indexOf(q) >= 0; }).slice(0, 6);
        hit.forEach(function (p, i) { var o = el('button', 'gm-sg' + (i === 0 ? ' on' : '')); o.type = 'button'; o.setAttribute('role', 'option'); o.appendChild(el('b', '', p.name)); o.appendChild(el('small', '', [p.role, p.committee].filter(Boolean).join(' · '))); o.addEventListener('mousedown', function (ev) { ev.preventDefault(); add(p); }); list.appendChild(o); });
        list.hidden = !hit.length; inp.setAttribute('aria-expanded', hit.length ? 'true' : 'false'); inp._hit = hit;
      }
      inp.addEventListener('input', suggest);
      inp.addEventListener('keydown', function (e) {
        if ((e.key === 'Enter' || e.key === 'Tab' || e.key === ',') && inp.value.trim()) { var h = inp._hit && inp._hit[0]; if (h) { e.preventDefault(); add(h); } }
        else if (e.key === 'Backspace' && !inp.value && W[fieldKey].length) { W[fieldKey].pop(); paint(); changed(); }
        else if (e.key === 'Escape' && !list.hidden) { e.stopPropagation(); list.hidden = true; }
      });
      inp.addEventListener('blur', function () { setTimeout(function () { list.hidden = true; }, 120); });
      paint(); r._paint = paint; return r;
    }
    var rTo = rowOf(tr('To', 'Para kay'), 'to'), rCc = rowOf('Cc', 'cc'), rBcc = rowOf('Bcc', 'bcc');
    var toggles = el('span', 'gm-w-tg'), bc = el('button', '', 'Cc'), bb = el('button', '', 'Bcc'); bc.type = 'button'; bb.type = 'button';
    bc.addEventListener('click', function () { rCc.hidden = false; bc.hidden = true; $('input', rCc).focus(); }); bb.addEventListener('click', function () { rBcc.hidden = false; bb.hidden = true; $('input', rBcc).focus(); });
    toggles.appendChild(bc); toggles.appendChild(bb); rTo.appendChild(toggles);
    rCc.hidden = !W.cc.length; rBcc.hidden = !W.bcc.length; bc.hidden = !rCc.hidden; bb.hidden = !rBcc.hidden;
    var rSub = el('div', 'gm-w-r'), sub = el('input', 'gm-w-in gm-w-sub'); sub.type = 'text'; sub.maxLength = 140; sub.placeholder = tr('Subject', 'Paksa'); sub.setAttribute('aria-label', tr('Subject', 'Paksa')); sub.value = W.subject; rSub.appendChild(sub);
    var ta = el('textarea', 'gm-w-body'); ta.maxLength = 4000; ta.setAttribute('aria-label', tr('Message', 'Mensahe')); ta.value = W.body;
    var tools = el('div', 'gm-w-tools'); tools.hidden = true;
    function wrap(a, b2) { var s = ta.selectionStart, e = ta.selectionEnd, v = ta.value; ta.value = v.slice(0, s) + a + v.slice(s, e) + b2 + v.slice(e); ta.focus(); ta.selectionStart = s + a.length; ta.selectionEnd = e + a.length; changed(); }
    function lines(prefix, num) { var s = ta.selectionStart, e = ta.selectionEnd, v = ta.value, a = v.lastIndexOf('\n', s - 1) + 1, seg = v.slice(a, e).split('\n').map(function (l, i) { return (num ? (i + 1) + '. ' : prefix) + l; }).join('\n'); ta.value = v.slice(0, a) + seg + v.slice(e); ta.focus(); changed(); }
    [['bold', tr('Bold', 'Bold'), function () { wrap('**', '**'); }], ['italic', tr('Italic', 'Italic'), function () { wrap('_', '_'); }], ['ul', tr('Bulleted list', 'Listahang may tuldok'), function () { lines('- ', false); }], ['ol', tr('Numbered list', 'Listahang may numero'), function () { lines('', true); }],
     ['quote', tr('Quote', 'Sipi'), function () { lines('> ', false); }], ['link', tr('Link', 'Link'), function () { wrap('https://', ''); }]].forEach(function (x) { var b = el('button', 'gm-w-tool'); b.type = 'button'; b.innerHTML = ic(x[0], 16); b.title = x[1]; b.setAttribute('aria-label', x[1]); b.addEventListener('click', x[2]); tools.appendChild(b); });
    var foot = el('div', 'gm-w-foot'), send = el('button', 'gm-btn gm-btn--blue gm-w-send', tr('Send', 'Ipadala')); send.type = 'button';
    function fbtn(icon, label, fn) { var b = el('button', 'gm-w-tool'); b.type = 'button'; b.innerHTML = ic(icon, 18); b.title = label; b.setAttribute('aria-label', label); b.addEventListener('click', fn); foot.appendChild(b); return b; }
    foot.appendChild(send);
    fbtn('fmt', tr('Formatting options', 'Mga opsyon sa format'), function () { tools.hidden = !tools.hidden; });
    var caseBox = el('input', 'gm-w-case'); caseBox.type = 'text'; caseBox.placeholder = tr('Case number', 'Numero ng kaso'); caseBox.setAttribute('aria-label', tr('Case to attach (its tracking number)', 'Kasong ilalakip (ang tracking number)')); caseBox.value = W.caseNo; caseBox.hidden = !W.caseNo;
    fbtn('case', tr('Attach a case', 'Maglakip ng kaso'), function () { caseBox.hidden = !caseBox.hidden; if (!caseBox.hidden) { caseBox.focus(); } });
    fbtn('face', tr('Insert emoji', 'Maglagay ng emoji'), function (e) { if (window.ssEmoji) { window.ssEmoji.open(e.currentTarget, function (em) { var s = ta.selectionStart; ta.value = ta.value.slice(0, s) + em + ta.value.slice(ta.selectionEnd); ta.focus(); ta.selectionStart = ta.selectionEnd = s + em.length; changed(); }); } });
    foot.appendChild(caseBox);
    var stat = el('span', 'gm-w-stat'); stat.setAttribute('role', 'status'); foot.appendChild(stat);
    var disc = el('button', 'gm-w-tool gm-w-disc'); disc.type = 'button'; disc.innerHTML = ic('trash', 18); disc.title = tr('Discard draft', 'Itapon ang draft'); disc.setAttribute('aria-label', tr('Discard draft', 'Itapon ang draft')); foot.appendChild(disc);
    var err = el('p', 'gm-w-err'); err.setAttribute('role', 'alert'); err.hidden = true;
    form.appendChild(rTo); form.appendChild(rCc); form.appendChild(rBcc); form.appendChild(rSub); form.appendChild(tools); form.appendChild(ta); form.appendChild(err); form.appendChild(foot);
    box.appendChild(head); box.appendChild(form);

    function snapshot() { return JSON.stringify([W.to, W.cc, W.bcc, sub.value, ta.value, caseBox.value]); }
    function hasContent() { return !!(W.to.length || W.cc.length || W.bcc.length || sub.value.trim() || ta.value.trim().length > 0 && ta.value.trim() !== W.body.trim() || (W.draftId && ta.value.trim())); }
    function save(final) {
      if (W.sending) { return Promise.resolve(); }
      var snap = snapshot(); if (snap === W.saved) { return Promise.resolve(); }
      if (!final && !(W.to.length || sub.value.trim() || ta.value.trim())) { return Promise.resolve(); }
      stat.textContent = tr('Saving…', 'Sine-save…');
      return post('draft_save', { id: W.draftId, to: W.to.map(function (p) { return p.id; }), cc: W.cc.map(function (p) { return p.id; }), bcc: W.bcc.map(function (p) { return p.id; }), subject: sub.value, body: ta.value, case: caseBox.value, reply_to: W.replyTo })
        .then(function (j) { if (j.ok) { W.draftId = j.id; W.saved = snap; stat.textContent = tr('Draft saved', 'Na-save ang draft'); if (S.folder === 'drafts' && S.view === 'list') { loadList(true); } } else { stat.textContent = j.text || tr('Could not save', 'Hindi na-save'); } });
    }
    function changed() { clearTimeout(W.timer); W.timer = setTimeout(function () { save(false); }, 1500); }
    [sub, ta, caseBox].forEach(function (i) { i.addEventListener('input', changed); });
    function close(keep) {
      clearTimeout(W.timer);
      var done = function () { if (W.inline) { box.remove(); if (S.thread) { var r = $('.gm-reply', readerEl); if (r) { r.hidden = false; } } } else { box.remove(); wins = wins.filter(function (x) { return x !== W; }); layout(); } };
      if (keep && (hasContent() || W.draftId)) { save(true).then(function () { done(); snack(tr('Draft saved.', 'Na-save ang draft.')); loadList(true); }); }
      else { if (W.draftId) { post('draft_delete', { id: W.draftId }); } done(); }
    }
    disc.addEventListener('click', function () { close(false); snack(tr('Draft discarded.', 'Naitapon ang draft.')); });
    function doSend() {
      err.hidden = true;
      if (!W.to.length && !W.cc.length && !W.bcc.length) { err.textContent = tr('Add at least one recipient.', 'Maglagay ng kahit isang tatanggap.'); err.hidden = false; return; }
      var payload = { to: W.to.map(function (p) { return p.id; }), cc: W.cc.map(function (p) { return p.id; }), bcc: W.bcc.map(function (p) { return p.id; }), subject: sub.value.trim() || tr('(no subject)', '(walang paksa)'), body: ta.value.trim() || '.', case: caseBox.value, reply_to: W.replyTo, draft: W.draftId };
      if (!ta.value.trim()) { err.textContent = tr('Write a message.', 'Sumulat ng mensahe.'); err.hidden = false; return; }
      W.sending = true; clearTimeout(W.timer); box.classList.add('gm-sending'); send.disabled = true;
      // Undo send: the message waits five seconds, and the window comes back if it is undone
      var cancelled = false, hide = box;
      hide.hidden = true;
      snack(tr('Sending…', 'Ipinapadala…'), function () { cancelled = true; W.sending = false; box.classList.remove('gm-sending'); send.disabled = false; hide.hidden = false; });
      setTimeout(function () {
        if (cancelled) { return; }
        post('send', payload).then(function (j) {
          if (!j.ok) { W.sending = false; box.classList.remove('gm-sending'); send.disabled = false; hide.hidden = false; err.textContent = j.text || tr('Could not send.', 'Hindi naipadala.'); err.hidden = false; hideSnack(); return; }
          box.remove(); if (!W.inline) { wins = wins.filter(function (x) { return x !== W; }); layout(); }
          snack(tr('Message sent.', 'Naipadala ang mensahe.'), null, { label: tr('View message', 'Tingnan ang mensahe'), fn: function () { go('#sent'); } });
          if (S.view === 'thread' && S.thread) { openThread(S.thread.id, true); } else { loadList(true); }
        });
      }, 5000);
    }
    send.addEventListener('click', doSend);
    box.addEventListener('keydown', function (e) { if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); doSend(); } else if (e.key === 'Escape' && !X.menu()) { e.stopPropagation(); close(true); } });

    if (W.inline) {
      var host = $('.gm-reply', readerEl); if (host) { host.hidden = true; }
      var pop = el('button', 'gm-w-b gm-w-pop'); pop.type = 'button'; pop.innerHTML = ic('pop', 16); pop.title = tr('Pop out', 'Ilabas'); pop.setAttribute('aria-label', tr('Pop out', 'Ilabas'));
      pop.addEventListener('click', function () { var c = { draftId: W.draftId, to: W.to, cc: W.cc, bcc: W.bcc, subject: sub.value, body: ta.value, caseNo: caseBox.value, replyTo: W.replyTo }; close(false); newCompose(c, {}); });
      head.appendChild(pop);
      head.className = 'gm-w-head gm-w-head--in'; readerEl.appendChild(box); box.scrollIntoView({ block: 'nearest' }); ta.focus(); ta.setSelectionRange(0, 0);
      var xb = el('button', 'gm-w-b'); xb.type = 'button'; xb.innerHTML = ic('x', 16); xb.setAttribute('aria-label', tr('Discard draft', 'Itapon ang draft')); xb.addEventListener('click', function () { close(true); }); head.appendChild(xb);
    } else {
      hbtn('min', tr('Minimize', 'I-minimize'), function () { box.classList.toggle('gm-min'); });
      hbtn('max', tr('Full screen', 'Buong screen'), function () { box.classList.toggle('gm-max'); });
      hbtn('x', tr('Save and close', 'I-save at isara'), function () { close(true); });
      head.addEventListener('click', function () { if (box.classList.contains('gm-min')) { box.classList.remove('gm-min'); } });
      $('#gm-wins').appendChild(box); wins.push(W); layout();
      (W.to.length ? (W.subject ? ta : sub) : $('input', rTo)).focus();
    }
    W.saved = init.draftId ? snapshot() : '';
    if (W.inline) { W.saved = snapshot(); }
    title.addEventListener('click', function () { });
    return W;
  }
  function layout() { var right = 24; wins.forEach(function () { }); $$('.gm-win', $('#gm-wins')).forEach(function (w, i) { w.style.right = (24 + i * 520) + 'px'; }); }
    return { composeFrom: composeFrom, openDraft: openDraft, newCompose: newCompose, count: function () { return wins.length; } };
  };
})();
