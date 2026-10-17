// Workspace widgets: the team (17 Oct 2026). Who is on duty and who is late, the roster and leave, who to call, what
// waits for approval, the Chairman's notice and announcements, handovers, the team board, a poll, birthdays, trainings
// and patrol checkpoints, and a one-tap check-in. Writes go through workspace-act.php; the database decides who may.
(function () {
  var WS = window.WS, T = WS.T, A = WS.a, esc = WS.esc, W = WS.w, L = WS.lvl;
  var ok = function (g) { return g && g.ok ? g.data : null; };
  var team = function () { return ok(WS.group('team')); };
  var DUTY = { on_duty: [T('On duty', 'Naka-duty'), '#2E9E4F'], break: [T('On a break', 'Nagpapahinga'), '#F5A524'], lunch: [T('At lunch', 'Kumakain'), '#F5A524'], offline: [T('Offline', 'Offline'), '#8E9ABB'] };
  var POS = { chairman: T('Chairman', 'Punong Barangay'), kagawad: T('Kagawad', 'Kagawad'), secretary: T('Secretary', 'Kalihim') };
  var av = function (name, c) { return esc(WS.initials(name)); };
  var today = function () { return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }); };
  var done = function (msg) { return function (r) { if (r && r.error) { WS.toast(r.error, true); return false; } if (msg) WS.toast(msg); WS.refresh(); return true; }; };
  var people = function (sel) { return (team() ? team().directory : []).map(function (p) { return '<option value="' + esc(p.id) + '"' + (p.id === sel ? ' selected' : '') + '>' + esc(WS.name(p.name)) + '</option>'; }).join(''); };
  var field = function (label, html) { return '<label class="wx-f"><span>' + label + '</span>' + html + '</label>'; };
  var posts = function (kind) { var d = ok(WS.group('posts')); return d ? d.posts.filter(function (p) { return p.kind === kind; }) : []; };
  var markSeen = function (list) { var ids = list.filter(function (p) { return !p.seen_by_me; }).map(function (p) { return p.id; }); if (ids.length) WS.post({ action: 'post_read', ids: ids.join(',') }); };
  var postRow = function (p) { return '<div class="wx-post' + (p.pinned ? ' is-pin' : '') + '"><div class="ph"><span class="wx-av" style="--c:#2D4FA8">' + av(p.author) + '</span><b>' + esc(WS.name(p.author || '')) + (p.author_position ? ' <small>' + esc(POS[p.author_position] || '') + '</small>' : '') + '</b><span class="wx-r">' + esc(WS.ago(p.at)) + (p.pinned ? ' · ' + WS.svg('pin', 12) : '') + '</span></div><p>' + esc(p.body) + '</p><div class="pf"><span class="wx-note">' + T('Seen by ' + p.seen + ' of ' + (ok(WS.group('posts')).staff || '?'), 'Nakita ng ' + p.seen + ' sa ' + (ok(WS.group('posts')).staff || '?')) + '</span>' + (p.mine || ok(WS.group('posts')).can_notice ? '<button type="button" class="wx-link" data-a="note:rm" data-id="' + esc(p.id) + '">' + T('Remove', 'Alisin') + '</button>' : '') + '</div></div>'; };
  function composer(kind, ph, max, hours) { return '<form class="wx-compose" data-s="note:send"><input type="hidden" name="kind" value="' + kind + '"><textarea name="body" rows="2" maxlength="' + max + '" placeholder="' + ph + '" aria-label="' + ph + '" required></textarea><div class="wx-row">' + (hours ? '<select name="pin_hours" aria-label="' + T('Pin for', 'I-pin nang') + '"><option value="0">' + T("Don't pin", 'Huwag i-pin') + '</option><option value="6">' + T('Pin 6 hours', 'I-pin nang 6 oras') + '</option><option value="24" selected>' + T('Pin 1 day', 'I-pin nang 1 araw') + '</option><option value="72">' + T('Pin 3 days', 'I-pin nang 3 araw') + '</option></select>' : '') + '<button class="wx-btn is-pri" style="margin-left:auto">' + T('Post', 'I-post') + '</button></div></form>'; }
  var postApi = { a: function (a, el) { if (a === 'rm') WS.post({ action: 'post_remove', id: el.dataset.id }).then(done(T('Removed.', 'Naalis.'))); },
    s: function (a, f) { var b = {}; ['kind', 'body', 'pin_hours'].forEach(function (k) { if (f[k]) b[k] = f[k].value; }); b.action = 'post'; WS.post(b).then(function (r) { if (done(T('Posted.', 'Na-post.'))(r)) f.reset(); }); } };
  function postWidget(id, kind, empty, ph, max, lead, hours, head) {
    W[id] = Object.assign({}, postApi, { r: function () {
      var d = ok(WS.group('posts')), l = posts(kind); if (kind === 'notice') l.sort(function (a, b) { return (b.pinned - a.pinned) || (new Date(b.at) - new Date(a.at)); });
      WS.after(function () { markSeen(l); });
      var can = !lead || d.can_notice;
      return (l.length ? '<div class="wx-list">' + l.slice(0, 4).map(postRow).join('') + '</div>' : A.empty('note', empty)) + (can ? composer(kind, ph, max, hours) : '<p class="wx-note">' + T('Only the Chairman or the Secretary posts here.', 'Ang Punong Barangay o ang Kalihim lamang ang nagpo-post dito.') + '</p>');
    } });
  }
  postWidget('note', 'notice', T('No notice from the Chairman right now', 'Walang paunawa mula sa Punong Barangay ngayon'), T('Write a notice for the whole team', 'Sumulat ng paunawa para sa buong koponan'), 1000, true, true);
  postWidget('bull', 'announcement', T('No announcements', 'Walang anunsyo'), T('Write an announcement', 'Sumulat ng anunsyo'), 1000, true, true);
  postWidget('shift', 'handover', T('Nothing was left by the last shift', 'Walang iniwan ang nakaraang shift'), T('What should the next shift know?', 'Ano ang dapat malaman ng susunod na shift?'), 1000, false, false);
  postWidget('board', 'board', T('The board is empty', 'Walang laman ang board'), T('A short line for the team (280 characters)', 'Maikling linya para sa koponan (280 titik)'), 280, false, false);

  // ---- who is on duty, attendance, roster, leave, trainings, birthdays, who to call, approvals
  W.duty = {
    r: function () {
      var t = team().tanods, on = t.filter(function (x) { return x.duty === 'on_duty'; }), free = on.filter(function (x) { return !x.jobs; });
      var order = { on_duty: 0, break: 1, lunch: 1, offline: 2 };
      t = t.slice().sort(function (a, b) { return (order[a.duty] - order[b.duty]) || a.name.localeCompare(b.name); });
      return '<div class="wx-row"><div class="wx-big" style="--c:' + L.ok + '"><b data-n="' + on.length + '">' + on.length + '</b><span>' + T('on duty now', 'naka-duty ngayon') + '</span></div><div class="wx-big" style="--c:' + L.normal + '"><b data-n="' + free.length + '">' + free.length + '</b><span>' + T('free to send', 'malayang maipadala') + '</span></div><div class="wx-big"><b data-n="' + on.reduce(function (s, x) { return s + x.jobs; }, 0) + '">0</b><span>' + T('jobs in hand', 'gawain') + '</span></div></div>' +
        (t.length ? '<div class="wx-list">' + t.map(function (x) { var d = DUTY[x.duty] || DUTY.offline; return A.item({ av: av(x.name), c: d[1], t: esc(WS.name(x.name)), s: esc(d[0]) + (x.since ? ' · ' + WS.ago(x.since).replace(T(' ago', ' ang nakalipas'), '') : '') + (x.jobs ? ' · ' + x.jobs + ' ' + T('job' + (x.jobs > 1 ? 's' : ''), 'gawain') : ''), r: x.duty === 'on_duty' ? A.pill(x.jobs ? T('Busy', 'Abala') : T('Free', 'Malaya'), x.jobs ? L.high : L.ok) : '' }); }).join('') + '</div>' : A.empty('people', T('No tanod accounts yet', 'Wala pang account ng tanod'))) + '<div class="wx-row"><a class="wx-btn" href="personnel.php">' + T('Personnel', 'Mga tauhan') + '</a></div>';
    }, src: 'Duty log'
  };
  W.attend = {
    r: function () {
      var t = team().tanods, here = t.filter(function (x) { return x.first_on; }), late = here.filter(function (x) { return x.late_minutes > 5; });
      return '<div class="wx-row"><div class="wx-big" style="--c:' + L.ok + '"><b data-n="' + here.length + '">' + here.length + '</b><span>' + T('clocked in today', 'pumasok ngayon') + '</span></div><div class="wx-big" style="--c:' + (late.length ? L.high : L.ok) + '"><b data-n="' + late.length + '">' + late.length + '</b><span>' + T('late', 'huli') + '</span></div></div><div class="wx-list">' + t.map(function (x) { var c = x.first_on ? (x.late_minutes > 5 ? L.high : L.ok) : L.low; return A.item({ av: av(x.name), c: c, t: esc(WS.name(x.name)), s: x.first_on ? T('In at ', 'Pumasok nang ') + esc(WS.fmt.time(x.first_on)) + (x.late_minutes > 5 ? ' · ' + x.late_minutes + ' min ' + T('late', 'huli') : x.rostered_hour != null ? ' · ' + T('on time', 'nasa oras') : '') : T('Not in yet', 'Hindi pa pumapasok'), r: '<b>' + (+x.hours_week).toFixed(1) + ' h</b> <small>' + T('this week', 'ngayong linggo') + '</small>' }); }).join('') + '</div><p class="wx-note">' + T('"Late" is measured against the roster; with no roster entry it is not counted.', 'Ang "huli" ay batay sa iskedyul; kung walang nakatalaga, hindi ito binibilang.') + '</p>';
    }, src: 'Duty log · roster'
  };
  var SH = [['morning', T('Morning', 'Umaga')], ['afternoon', T('Afternoon', 'Hapon')], ['night', T('Night', 'Gabi')]];
  W.roster = {
    r: function () {
      var t = team(), days = [], base = new Date(today() + 'T12:00:00+08:00');
      for (var i = 0; i < 7; i++) days.push(new Date(base.getTime() + i * 864e5).toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }));
      return '<div class="wx-roster">' + days.map(function (d, i) { var rs = t.roster.filter(function (x) { return x.date === d; }); return '<div class="rd' + (i === 0 ? ' now' : '') + '"><b>' + (i === 0 ? T('Today', 'Ngayon') : esc(WS.fmt.wd(d + 'T12:00:00+08:00'))) + '</b><small>' + esc(WS.fmt.day(d + 'T12:00:00+08:00')) + '</small>' + (rs.length ? SH.map(function (s) { var p = rs.filter(function (x) { return x.shift === s[0]; }); return p.length ? '<div class="sh sh-' + s[0] + '"><i>' + s[1].slice(0, 1) + '</i>' + p.map(function (x) { return '<span title="' + esc(WS.name(x.name)) + '">' + esc(WS.name(x.name).split(' ')[0]) + '<button type="button" data-a="roster:rm" data-id="' + esc(x.id) + '" aria-label="' + T('Remove', 'Alisin') + '">×</button></span>'; }).join('') + '</div>' : ''; }).join('') : '<span class="none">–</span>') + '</div>'; }).join('') + '</div>' +
        '<form class="wx-compose wx-inline" data-s="roster:add">' + field(T('Who', 'Sino'), '<select name="user_id">' + people() + '</select>') + field(T('Day', 'Araw'), '<input type="date" name="date" value="' + today() + '" min="' + today() + '">') + field(T('Shift', 'Shift'), '<select name="shift">' + SH.map(function (s) { return '<option value="' + s[0] + '">' + s[1] + ' · ' + (t.shift_starts[SH.indexOf(s)]) + ':00</option>'; }).join('') + '</select>') + '<button class="wx-btn is-pri">' + T('Add', 'Idagdag') + '</button></form>';
    },
    a: function (a, el) { if (a === 'rm') WS.post({ action: 'roster_remove', id: el.dataset.id }).then(done()); },
    s: function (a, f) { WS.post({ action: 'roster_add', user_id: f.user_id.value, date: f.date.value, shift: f.shift.value }).then(done(T('Added to the roster.', 'Naidagdag sa iskedyul.'))); }, src: 'Roster'
  };
  W.leave = {
    r: function () {
      var l = team().leave;
      return (l.length ? '<div class="wx-list">' + l.map(function (x) { return A.item({ av: av(x.name), c: x.now ? L.high : L.low, t: esc(WS.name(x.name)), s: esc(WS.fmt.day(x.from + 'T12:00:00+08:00')) + ' – ' + esc(WS.fmt.day(x.to + 'T12:00:00+08:00')) + (x.reason ? ' · ' + esc(x.reason) : ''), r: (x.now ? A.pill(T('off now', 'liban ngayon'), L.high) : '') + ' <button type="button" class="wx-link" data-a="leave:rm" data-id="' + esc(x.id) + '">' + T('Remove', 'Alisin') + '</button>' }); }).join('') + '</div>' : A.empty('people', T('Nobody is on leave', 'Walang naka-leave'))) +
        '<form class="wx-compose wx-inline" data-s="leave:add">' + field(T('Who', 'Sino'), '<select name="user_id">' + people() + '</select>') + field(T('From', 'Mula'), '<input type="date" name="from" value="' + today() + '">') + field(T('To', 'Hanggang'), '<input type="date" name="to" value="' + today() + '">') + field(T('Why', 'Dahilan'), '<input name="reason" maxlength="200">') + '<button class="wx-btn is-pri">' + T('Add', 'Idagdag') + '</button></form>';
    },
    a: function (a, el) { if (a === 'rm') WS.post({ action: 'leave_remove', id: el.dataset.id }).then(done()); },
    s: function (a, f) { WS.post({ action: 'leave_add', user_id: f.user_id.value, from: f.from.value, to: f.to.value, reason: f.reason.value }).then(done(T('Saved.', 'Na-save.'))); }
  };
  var CK = { first_aid: T('First aid', 'Unang lunas'), tanod_id: T('Tanod ID', 'ID ng tanod'), training: T('Training', 'Training'), other: T('Other', 'Iba pa') };
  W.train = {
    r: function () {
      var c = team().credentials;
      return (c.length ? '<div class="wx-list">' + c.map(function (x) { var d = x.days_left, col = d == null ? L.low : d < 0 ? L.urgent : d <= 30 ? L.high : L.ok; return A.item({ av: av(x.name), c: col, t: esc(x.label) + ' · ' + esc(WS.name(x.name)), s: esc(CK[x.kind] || '') + (x.expires_on ? ' · ' + (d < 0 ? T('expired ', 'nag-expire noong ') : T('expires ', 'mag-e-expire sa ')) + esc(WS.fmt.day(x.expires_on + 'T12:00:00+08:00')) : ' · ' + T('no expiry', 'walang expiry')), r: d != null && d <= 30 ? A.pill(d < 0 ? T('expired', 'expired') : d + ' ' + T('days', 'araw'), col) : '<button type="button" class="wx-link" data-a="train:rm" data-id="' + esc(x.id) + '">' + T('Remove', 'Alisin') + '</button>' }); }).join('') + '</div>' : A.empty('shield', T('No IDs or trainings recorded', 'Walang naitalang ID o training'))) +
        '<form class="wx-compose wx-inline" data-s="train:add">' + field(T('Who', 'Sino'), '<select name="user_id">' + people() + '</select>') + field(T('Kind', 'Uri'), '<select name="kind">' + Object.keys(CK).map(function (k) { return '<option value="' + k + '">' + CK[k] + '</option>'; }).join('') + '</select>') + field(T('Name', 'Pangalan'), '<input name="label" maxlength="120" required placeholder="Red Cross first aid">') + field(T('Expires', 'Mag-e-expire'), '<input type="date" name="expires">') + '<button class="wx-btn is-pri">' + T('Add', 'Idagdag') + '</button></form>';
    },
    a: function (a, el) { if (a === 'rm') WS.post({ action: 'cred_remove', id: el.dataset.id }).then(done()); },
    s: function (a, f) { WS.post({ action: 'cred_add', user_id: f.user_id.value, kind: f.kind.value, label: f.label.value, expires: f.expires.value }).then(done(T('Saved.', 'Na-save.'))); }
  };
  W.bday = {
    r: function () {
      var b = team().birthdays;
      return (b.length ? '<div class="wx-list">' + b.map(function (x) { return A.item({ av: '🎂', c: '#E8438B', t: esc(WS.name(x.name)), s: x.in_days === 0 ? T('Today!', 'Ngayon!') : x.in_days === 1 ? T('Tomorrow', 'Bukas') : esc(WS.fmt.wdl(x.on + 'T12:00:00+08:00')) + ', ' + esc(WS.fmt.day(x.on + 'T12:00:00+08:00')), r: x.in_days === 0 ? A.pill(T('Greet them', 'Batiin sila'), '#E8438B') : x.in_days + ' ' + T('days', 'araw') }); }).join('') + '</div>' : A.empty('star', T('No birthdays in the next two weeks', 'Walang kaarawan sa susunod na dalawang linggo'))) +
        '<form class="wx-compose wx-inline" data-s="bday:set">' + field(T('Who', 'Sino'), '<select name="user_id">' + people() + '</select>') + field(T('Birthday', 'Kaarawan'), '<input type="date" name="date" required>') + '<button class="wx-btn is-pri">' + T('Save', 'I-save') + '</button></form>';
    },
    s: function (a, f) { WS.post({ action: 'birthday', user_id: f.user_id.value, date: f.date.value }).then(done(T('Saved.', 'Na-save.'))); }
  };
  W.dir = {
    r: function () {
      var d = team().directory;
      return '<div class="wx-list">' + d.map(function (x) { var c = x.position === 'chairman' ? L.urgent : x.position === 'kagawad' ? '#6A4FD3' : x.role === 'tanod' ? '#00A5B5' : '#2D4FA8'; return A.item({ av: av(x.name), c: c, t: esc(WS.name(x.name)), s: esc(POS[x.position] || (x.role === 'tanod' ? T('Tanod', 'Tanod') : T('Staff', 'Kawani'))) + (x.mobile ? ' · ' + esc(x.mobile) : ''), r: x.mobile ? '<button type="button" class="wx-btn is-sm" data-a="dir:cp" data-v="' + esc(x.mobile) + '">' + T('Copy', 'Kopyahin') + '</button>' : '' }); }).join('') + '</div>';
    },
    a: function (a, el) { if (a === 'cp') WS.copy(el.dataset.v); }
  };
  WS.copy = function (v) { var okc = function () { WS.toast(T('Copied: ', 'Nakopya: ') + v); }; if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(v).then(okc, function () { WS.toast(v); }); else { var t = document.createElement('textarea'); t.value = v; document.body.appendChild(t); t.select(); try { document.execCommand('copy'); okc(); } catch (e) { WS.toast(v); } t.remove(); } };
  W.req = {
    r: function () {
      var w = team().waiting, rows = [[T('Residents to verify', 'Residenteng ibe-verify'), w.residents, 'residents.php', w.residents_oldest ? T('oldest ', 'pinakamatagal ') + WS.ago(w.residents_oldest).replace(T(' ago', ' ang nakalipas'), '') : ''], [T('Name and ID requests', 'Kahilingang pangalan at ID'), w.profile_requests, 'residents.php', ''], [T('Retirement requests', 'Kahilingang mag-retiro'), w.retirements, 'retirement-requests.php', ''], [T('Requests to pass a case up', 'Kahilingang mag-akyat ng kaso'), w.escalations, 'workspace.php', '']];
      var tot = rows.reduce(function (s, r) { return s + r[1]; }, 0);
      if (!tot) return A.empty('check', T('Nothing is waiting for you', 'Walang naghihintay sa iyo'));
      return '<div class="wx-big" style="--c:' + L.high + '"><b data-n="' + tot + '">' + tot + '</b><span>' + T('waiting for a decision', 'naghihintay ng desisyon') + '</span></div><div class="wx-list">' + rows.filter(function (r) { return r[1]; }).map(function (r) { return A.item({ href: r[2], av: r[1], c: L.high, sq: 1, t: esc(r[0]), s: esc(r[3]), r: '<span class="wx-go">' + T('Review', 'Suriin') + WS.svg('up', 12, 2.6) + '</span>' }); }).join('') + '</div>';
    }
  };

  // ---- a poll, patrol checkpoints, the check-in
  W.poll = {
    r: function () {
      var p = ok(WS.group('polls')), cur = p.filter(function (x) { return x.open; })[0] || p[0];
      var make = '<details class="wx-det"><summary>' + T('Ask the team something', 'Magtanong sa koponan') + '</summary><form class="wx-compose" data-s="poll:make">' + field(T('Question', 'Tanong'), '<input name="question" maxlength="200" required placeholder="' + T('Who can cover Saturday night?', 'Sino ang puwedeng sumalo sa Sabado ng gabi?') + '">') + field(T('Answers, one per line (2 to 6)', 'Mga sagot, isa bawat linya (2 hanggang 6)'), '<textarea name="options" rows="3" required></textarea>') + '<div class="wx-row"><select name="close_hours"><option value="24">' + T('Closes in 1 day', 'Magsasara sa 1 araw') + '</option><option value="72">' + T('Closes in 3 days', 'Magsasara sa 3 araw') + '</option><option value="0">' + T('Stays open', 'Mananatiling bukás') + '</option></select><button class="wx-btn is-pri" style="margin-left:auto">' + T('Ask', 'Itanong') + '</button></div></form></details>';
      if (!cur) return A.empty('chart', T('No poll right now', 'Walang botohan ngayon')) + make;
      var tot = cur.votes.reduce(function (s, x) { return s + x; }, 0);
      return '<div class="wx-card2"><b style="font:800 16px Urbanist">' + esc(cur.question) + '</b><span class="wx-note">' + esc(WS.name(cur.author || '')) + ' · ' + (cur.open ? T('open', 'bukás') : T('closed', 'sarado')) + ' · ' + tot + ' ' + T('votes', 'boto') + '</span>' + cur.options.map(function (o, i) { var v = cur.votes[i] || 0, pc = tot ? Math.round(v / tot * 100) : 0, mine = cur.my_vote === i; return '<button type="button" class="wx-opt' + (mine ? ' is-mine' : '') + '" data-a="poll:vote" data-p="' + esc(cur.id) + '" data-c="' + i + '"' + (cur.open ? '' : ' disabled') + ' style="--p:' + pc + '%"><i></i><span>' + esc(o) + (mine ? ' ✓' : '') + '</span><b>' + v + ' · ' + pc + '%</b></button>'; }).join('') + (cur.open && cur.mine ? '<button type="button" class="wx-link" data-a="poll:close" data-p="' + esc(cur.id) + '">' + T('Close this poll', 'Isara ang botohang ito') + '</button>' : '') + '</div>' + make;
    },
    a: function (a, el) { if (a === 'vote') WS.post({ action: 'vote', poll_id: el.dataset.p, choice: el.dataset.c }).then(done()); else if (a === 'close') WS.post({ action: 'poll_close', id: el.dataset.p }).then(done()); },
    s: function (a, f) { WS.post({ action: 'poll', question: f.question.value, options: f.options.value, close_hours: f.close_hours.value }).then(done(T('Poll started.', 'Nagsimula ang botohan.'))); }
  };
  W.checkpt = {
    r: function () {
      var c = ok(WS.group('checkpoints'));
      return (c.length ? '<div class="wx-list">' + c.map(function (x, i) { var d = x.today; return A.item({ av: d ? '✓' : (i + 1), c: d ? L.ok : L.low, sq: 1, t: esc(x.name), s: d ? T('Reached at ', 'Narating nang ') + esc(WS.fmt.time(d.at)) + ' · ' + esc(WS.name(d.tanod || '')) : T('Not reached today', 'Hindi pa narating ngayon'), r: '<select data-c="checkpt:scan" data-cp="' + esc(x.id) + '" aria-label="' + T('Mark reached by', 'Markahang narating ni') + '"><option value="">' + T('Mark reached…', 'Markahan…') + '</option>' + team().tanods.map(function (t) { return '<option value="' + esc(t.id) + '">' + esc(WS.name(t.name)) + '</option>'; }).join('') + '</select>' }); }).join('') + '</div>' : A.empty('flag', T('No checkpoints yet', 'Wala pang checkpoint'))) +
        '<form class="wx-compose wx-inline" data-s="checkpt:add">' + field(T('New checkpoint', 'Bagong checkpoint'), '<input name="name" maxlength="120" required placeholder="' + T('Libertad Market', 'Palengke ng Libertad') + '">') + '<button type="button" class="wx-btn" data-a="checkpt:here">' + WS.svg('pin', 14) + T('Use my place', 'Gamitin ang lugar ko') + '</button><input type="hidden" name="lat" value="14.5194"><input type="hidden" name="lng" value="121.0122"><button class="wx-btn is-pri">' + T('Add', 'Idagdag') + '</button></form><p class="wx-note">' + T('Without "Use my place" a checkpoint is put at the barangay hall.', 'Kung hindi gagamitin ang "Gamitin ang lugar ko", ilalagay ang checkpoint sa barangay hall.') + '</p>';
    },
    ch: function (a, el) { if (a === 'scan' && el.value) WS.post({ action: 'scan', checkpoint_id: el.dataset.cp, tanod_id: el.value }).then(done(T('Recorded.', 'Naitala.'))); },
    a: function (a, el) { if (a === 'here') { if (!navigator.geolocation) return WS.toast(T('This device cannot tell where it is.', 'Hindi malaman ng device ang lugar nito.'), true); navigator.geolocation.getCurrentPosition(function (p) { var f = el.closest('form'); f.lat.value = p.coords.latitude.toFixed(6); f.lng.value = p.coords.longitude.toFixed(6); el.classList.add('is-pri'); WS.toast(T('Place noted.', 'Naitala ang lugar.')); }, function () { WS.toast(T('Could not read your place.', 'Hindi mabasa ang lugar mo.'), true); }); } },
    s: function (a, f) { WS.post({ action: 'cp_add', name: f.name.value, lat: f.lat.value, lng: f.lng.value }).then(done(T('Checkpoint added.', 'Naidagdag ang checkpoint.'))); }
  };
  W.mood = {
    r: function () {
      var m = ok(WS.group('mood')), tot = m.totals, M = [['calm', '🙂', T('Calm', 'Kalmado')], ['busy', '😐', T('Busy', 'Abala')], ['tired', '😮‍💨', T('Tired', 'Pagod')]];
      return '<div class="wx-card2"><b style="font:800 15px Urbanist">' + T('How is the shift going?', 'Kumusta ang shift?') + '</b><div class="wx-moods">' + M.map(function (x) { return '<button type="button" class="wx-mood' + (m.mine === x[0] ? ' is-on' : '') + '" data-a="mood:set" data-m="' + x[0] + '" aria-pressed="' + (m.mine === x[0]) + '"><span>' + x[1] + '</span><b>' + x[2] + '</b></button>'; }).join('') + '</div><p class="wx-note">' + (m.mine ? T('Thanks. You can change it today.', 'Salamat. Maaari mo itong baguhin ngayon.') : T('One tap. Only the totals are ever shown, never who.', 'Isang pindot. Kabuuan lamang ang ipinapakita, hindi kung sino.')) + '</p></div>' +
        (tot ? (tot.hidden ? '<p class="wx-note">' + T('Totals show once three people have answered (' + tot.answered + ' so far).', 'Lalabas ang kabuuan kapag tatlo na ang sumagot (' + tot.answered + ' pa lang).') + '</p>' : '<div class="wx-card2"><span class="wx-h">' + T('The team today', 'Ang koponan ngayon') + '</span><div class="wx-stack">' + M.map(function (x, i) { return tot[x[0]] ? '<i style="flex:' + tot[x[0]] + ';background:' + [L.ok, L.high, L.urgent][i] + '"></i>' : ''; }).join('') + '</div><div class="wx-row">' + M.map(function (x) { return '<span class="wx-note">' + x[1] + ' ' + tot[x[0]] + '</span>'; }).join('') + '</div></div>') : '');
    },
    a: function (a, el) { WS.post({ action: 'mood', mood: el.dataset.m }).then(done()); }
  };
})();
