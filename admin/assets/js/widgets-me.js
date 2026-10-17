// Workspace widgets: just for me (17 Oct 2026). A checklist, a sticky note, a countdown, a water reminder, a goal for the
// week, a line for the shift, daily habits and notes for the next shift. Each person's own, kept with their account.
(function () {
  var WS = window.WS, T = WS.T, A = WS.a, esc = WS.esc, n = WS.n, W = WS.w, L = WS.lvl, M = WS.mine;
  var ok = function (g) { return g && g.ok ? g.data : null; };
  var today = function () { return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }); };
  var field = function (label, html) { return '<label class="wx-f"><span>' + label + '</span>' + html + '</label>'; };
  var lone = function () { return '<p class="wx-note">' + T('Only you see this. It follows your account to any device.', 'Ikaw lamang ang nakakakita nito. Sumusunod ito sa account mo sa anumang device.') + '</p>'; };

  W.todo = {
    r: function () {
      var l = M.get('todo', []), left = l.filter(function (x) { return !x.d; }).length;
      return '<div class="wx-row"><div class="wx-big" style="--c:' + (left ? L.high : L.ok) + '"><b data-n="' + left + '">' + left + '</b><span>' + T('left to do', 'natitirang gawin') + '</span></div>' + (l.length - left ? '<button type="button" class="wx-btn is-sm" style="margin-left:auto" data-a="todo:clear">' + T('Clear done', 'Alisin ang tapos') + '</button>' : '') + '</div>' +
        '<form class="wx-add1" data-s="todo:add"><input name="t" maxlength="120" placeholder="' + T('Add something to do', 'Magdagdag ng gagawin') + '" aria-label="' + T('New to-do', 'Bagong gagawin') + '" autocomplete="off"><button class="wx-btn is-pri">' + T('Add', 'Idagdag') + '</button></form>' +
        (l.length ? '<div class="wx-list">' + l.map(function (x, i) { return '<div class="wx-todo' + (x.d ? ' is-done' : '') + '"><button type="button" role="checkbox" aria-checked="' + !!x.d + '" data-a="todo:tick" data-i="' + i + '" aria-label="' + esc(x.t) + '"><span>' + (x.d ? WS.svg('check', 14, 3.2) : '') + '</span></button><b>' + esc(x.t) + '</b><button type="button" class="wx-x2" data-a="todo:rm" data-i="' + i + '" aria-label="' + T('Remove', 'Alisin') + '">' + WS.svg('cross', 14) + '</button></div>'; }).join('') + '</div>' : A.empty('check', T('Nothing on your list', 'Walang laman ang listahan mo'))) + lone();
    },
    a: function (a, el) { var l = M.get('todo', []), i = +el.dataset.i; if (a === 'tick') l[i].d = !l[i].d; else if (a === 'rm') l.splice(i, 1); else if (a === 'clear') l = l.filter(function (x) { return !x.d; }); M.set('todo', l); WS.rerender(); },
    s: function (a, f) { var t = f.t.value.trim(); if (!t) return; var l = M.get('todo', []); if (l.length >= 40) { WS.toast(T('That is a long list. Clear some first.', 'Mahaba na ang listahan. Alisin muna ang ilan.'), true); return; } l.unshift({ t: t, d: 0 }); M.set('todo', l); WS.rerender(); var i = document.querySelector('.wx-add1 input'); if (i) i.focus(); }
  };

  function textWidget(key, label, ph, cls) {
    return { r: function () { return '<div class="wx-note-pad ' + cls + '"><textarea data-i="' + key + ':type" maxlength="3000" rows="9" placeholder="' + ph + '" aria-label="' + label + '">' + esc(M.get(key, '')) + '</textarea><span class="wx-saved" aria-live="polite"></span></div>' + lone(); },
      n: function (a, el) { var v = el.value; clearTimeout(this.t); var s = el.parentNode.querySelector('.wx-saved'); if (s) s.textContent = T('Saving…', 'Sine-save…'); this.t = setTimeout(function () { M.set(key, v); if (s) s.textContent = T('Saved', 'Na-save'); }, 600); } };
  }
  W.sticky = textWidget('sticky', T('Sticky note', 'Sticky note'), T('Ask Kagawad about the new drainage schedule…', 'Tanungin ang Kagawad tungkol sa bagong iskedyul ng drainage…'), 'yel');
  W.shiftn = textWidget('shiftn', T('Notes for the next shift', 'Tala para sa susunod na shift'), T('Remind the day shift: …', 'Ipaalala sa day shift: …'), 'blu');

  W.count = {
    r: function () {
      var c = M.get('count', null), set = '<form class="wx-compose wx-inline" data-s="count:set">' + field(T('Name', 'Pangalan'), '<input name="name" maxlength="60" required value="' + esc(c ? c.name : '') + '" placeholder="' + T('Barangay assembly', 'Asembleya ng barangay') + '">') + field(T('Date', 'Petsa'), '<input type="date" name="date" required value="' + esc(c ? c.date : today()) + '">') + '<button class="wx-btn is-pri">' + T('Save', 'I-save') + '</button></form>';
      if (!c) return A.empty('clock', T('Count down to something', 'Magbilang pababa sa isang petsa')) + set + lone();
      var d = Math.round((new Date(c.date + 'T00:00:00+08:00') - new Date(today() + 'T00:00:00+08:00')) / 864e5);
      return '<div class="wx-hero" style="--hg:linear-gradient(135deg,#1C2A52,#2D4FA8);--hc:#356CF9"><span class="eb">' + esc(c.name) + '</span><div class="hb" style="font-size:52px">' + (d < 0 ? Math.abs(d) : d) + '</div><p class="hs">' + (d === 0 ? T('Today!', 'Ngayon na!') : d < 0 ? T('days ago', 'araw na ang nakalipas') : d === 1 ? T('day to go', 'araw na lang') : T('days to go', 'araw na lang')) + ' · ' + esc(WS.fmt.wdl(c.date + 'T12:00:00+08:00') + ', ' + WS.fmt.day(c.date + 'T12:00:00+08:00')) + '</p></div>' + set + lone();
    },
    s: function (a, f) { M.set('count', { name: f.name.value.trim(), date: f.date.value }); WS.rerender(); }
  };

  var GL = 8;
  W.water = {
    opt: ['wx'],
    r: function () {
      var w = M.get('water', {}), cnt = w.d === today() ? w.n : 0, wx = ok(WS.group('wx')), h = wx ? wx.heat.c : null, every = h != null && h >= 33 ? 1 : 2;
      var hour = +new Date().toLocaleString('en-US', { timeZone: 'Asia/Manila', hour: 'numeric', hour12: false }) % 24, due = Math.max(0, Math.min(GL, Math.floor((hour - 6) / every) + 1));
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center">' + A.ring(cnt / GL * 100, '#2D7DD2', cnt + '/' + GL, T('glasses', 'baso')) + '<button type="button" class="wx-btn is-pri" data-a="water:add">' + WS.svg('drop', 15) + T('I drank', 'Uminom ako') + '</button></div><div class="wx-card2"><div class="wx-glasses">' + Array.apply(null, Array(GL)).map(function (_, i) { return '<i class="' + (i < cnt ? 'on' : i < due ? 'due' : '') + '"></i>'; }).join('') + '</div><p>' + (h != null && h >= 33 ? T('It feels like ' + h + '° out. Drink every hour on foot rounds.', 'Parang ' + h + '° sa labas. Uminom kada oras sa ronda.') : T('A glass every couple of hours keeps you sharp.', 'Ang isang baso kada ilang oras ay nagpapanatiling alerto sa iyo.')) + '</p>' + (cnt < due ? '<span class="wx-pill" style="--c:' + L.high + '">' + T((due - cnt) + ' behind', 'kulang ng ' + (due - cnt)) + '</span>' : cnt >= GL ? '<span class="wx-pill" style="--c:' + L.ok + '">' + T('Done for today', 'Tapos na ngayon') + '</span>' : '') + '</div></div>' + lone();
    },
    a: function (a) { var w = M.get('water', {}); if (w.d !== today()) w = { d: today(), n: 0 }; w.n = Math.min(GL + 4, w.n + 1); M.set('water', w); WS.rerender(); }
  };

  W.goal = {
    opt: ['mine'],
    r: function () {
      var g = M.get('goal', null), m = ok(WS.group('mine')), set = '<form class="wx-compose wx-inline" data-s="goal:set">' + field(T('Close this many cases this week', 'Isara ang ganito karaming kaso ngayong linggo'), '<input type="number" name="target" min="1" max="200" required value="' + (g ? g.target : 5) + '">') + '<button class="wx-btn is-pri">' + T('Set my goal', 'Itakda ang layunin') + '</button></form>';
      if (!g) return A.empty('flag', T('Set a goal for the week', 'Magtakda ng layunin para sa linggo')) + set + lone();
      var done = m ? (m.closed_this_week || 0) : 0, pc = Math.min(100, Math.round(done / g.target * 100)), left = Math.max(0, g.target - done), wd = (new Date(today() + 'T12:00:00+08:00').getDay() + 6) % 7, days = 7 - wd;
      return '<div class="wx-grid2"><div class="wx-card2" style="place-items:center">' + A.ring(pc, pc >= 100 ? L.ok : '#FF9800', done + '/' + g.target, T('cases closed', 'kasong naisara')) + '</div><div class="wx-card2"><b style="font:800 16px Urbanist">' + (pc >= 100 ? T('Goal reached!', 'Naabot ang layunin!') : left + ' ' + T('to go', 'na lang')) + '</b><p>' + (pc >= 100 ? T('Beyond the goal is a bonus. Well done.', 'Bonus na ang lampas sa layunin. Magaling.') : T(days + ' day' + (days > 1 ? 's' : '') + ' left this week.', days + ' araw pa ngayong linggo.')) + '</p>' + (m ? A.kv([[T('Cases you hold open', 'Bukás na kasong hawak mo'), m.open]]) : '') + '</div></div>' + set + '<p class="wx-note">' + T('Counts the cases you closed since Monday.', 'Binibilang ang mga kasong naisara mo mula Lunes.') + '</p>';
    },
    s: function (a, f) { M.set('goal', { target: Math.max(1, Math.min(200, +f.target.value || 5)) }); WS.rerender(); }
  };

  var Q = [[T('Peace is not the absence of calls; it is how well we answer them.', 'Ang kapayapaan ay hindi kawalan ng tawag; ito ay kung gaano natin kahusay sagutin ang mga ito.')], [T('A calm voice is the first tool of every tanod.', 'Ang mahinahong boses ang unang kasangkapan ng bawat tanod.')], [T('Listen first. Most disputes want to be heard before they want to be settled.', 'Makinig muna. Karamihan sa alitan ay gustong marinig bago maareglo.')], [T('Write it down while it is fresh; tomorrow you will thank yourself.', 'Isulat habang sariwa; magpapasalamat ka bukas.')], [T('Bayanihan: no one carries a house alone.', 'Bayanihan: walang nagbubuhat ng bahay nang mag-isa.')], [T('The kindest report is the one that is complete.', 'Ang pinakamabait na ulat ay ang kumpleto.')], [T('Every resolved case is a family that sleeps better tonight.', 'Bawat nalutas na kaso ay isang pamilyang mas makakatulog nang maayos ngayong gabi.')]];
  W.mantra = {
    r: function () { var d = Math.floor(Date.now() / 864e5), q = Q[d % Q.length]; return '<div class="wx-hero" style="--hg:linear-gradient(135deg,#3B1F6B,#C2410C);--hc:#FF9800"><span class="eb">' + T('For this shift', 'Para sa shift na ito') + '</span><div class="hb" style="font-size:24px;line-height:1.25">“' + esc(q[0]) + '”</div></div><p class="wx-note">' + T('A new line each day.', 'Bagong linya bawat araw.') + '</p>'; }
  };

  var HB = [['water', T('Drink water', 'Uminom ng tubig'), 'drop', '#2D7DD2'], ['stretch', T('Stretch', 'Mag-unat'), 'pulse', '#2E9E4F'], ['notes', T('Write the shift notes', 'Isulat ang tala ng shift'), 'note', '#FF9800'], ['eat', T('Eat something proper', 'Kumain nang maayos'), 'heart', '#E8438B'], ['call', T('Call home', 'Tumawag sa bahay'), 'phone', '#8E3FD0']];
  W.habit = {
    r: function () {
      var h = M.get('habit', {}), d = h.d === today() ? h.done || {} : {}, c = HB.filter(function (x) { return d[x[0]]; }).length, streak = h.streak || 0;
      return '<div class="wx-row"><div class="wx-big" style="--c:#2E9E4F"><b data-n="' + c + '">' + c + '</b><span>' + T('of ' + HB.length + ' today', 'sa ' + HB.length + ' ngayon') + '</span></div>' + (streak > 1 ? '<span class="wx-pill" style="--c:#FF9800;margin-left:auto">🔥 ' + streak + ' ' + T('days in a row', 'araw nang sunod-sunod') + '</span>' : '') + '</div><div class="wx-list">' + HB.map(function (x) { var on = !!d[x[0]]; return '<button type="button" class="wx-hab' + (on ? ' is-on' : '') + '" data-a="habit:tick" data-k="' + x[0] + '" aria-pressed="' + on + '" style="--c:' + x[3] + '"><span class="ic">' + WS.svg(x[2], 18) + '</span><b>' + esc(x[1]) + '</b><span class="ck">' + (on ? WS.svg('check', 14, 3.2) : '') + '</span></button>'; }).join('') + '</div>' + lone();
    },
    a: function (a, el) {
      var h = M.get('habit', {}); if (h.d !== today()) { var y = new Date(Date.now() - 864e5).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }), all = h.d === y && HB.every(function (x) { return (h.done || {})[x[0]]; }); h = { d: today(), done: {}, streak: all ? (h.streak || 0) : 0, last: h.last }; }
      h.done[el.dataset.k] = !h.done[el.dataset.k];
      if (HB.every(function (x) { return h.done[x[0]]; }) && h.last !== today()) { h.streak = (h.streak || 0) + 1; h.last = today(); WS.toast(T('All done for today!', 'Tapos na lahat ngayon!')); }
      M.set('habit', h); WS.rerender();
    }
  };
})();
