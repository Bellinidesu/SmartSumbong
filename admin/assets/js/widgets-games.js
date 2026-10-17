// Workspace widgets: minigames (17 Oct 2026). Fourteen small games for a quiet minute on a long shift. They are off
// until the Chairman or the Secretary allows them, and each keeps a personal best and a team top three.
(function () {
  var WS = window.WS, T = WS.T, A = WS.a, esc = WS.esc, W = WS.w, L = WS.lvl;
  var ok = function (g) { return g && g.ok ? g.data : null; };
  var rnd = function (m) { return Math.floor(Math.random() * m); };
  var day = function () { return Math.floor(Date.now() / 864e5); };
  var today = function () { return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' }); };
  var LOW = ['mem', 'react', 'whack', 'wordl', 'sudoku', 'mines'];
  var UNIT = { mem: T(' moves', ' galaw'), react: ' ms', whack: ' s', wordl: T(' tries', ' subok'), sudoku: ' s', mines: ' s', quiz: '/10', type: ' wpm', ttt: T(' wins', ' panalo'), rps: T(' wins', ' panalo'), hl: T(' in a row', ' sunod-sunod'), snake: '', g2048: '', simon: T(' rounds', ' round') };
  var fmt = function (g, v) { return (g === 'whack' ? (v / 1000).toFixed(1) : v) + (UNIT[g] || ''); };

  // every game goes through here: the off card, the board, and the best scores
  function game(id, def) {
    var render = def.r;
    def.r = function () {
      var g = ok(WS.group('games'));
      if (!g.enabled) return '<div class="wx-empty">' + WS.svg('game', 30, 1.5) + '<b>' + T('Minigames are switched off', 'Naka-off ang mga minigame') + '</b><span>' + T('The Chairman or the Secretary can allow them under Widgets, at the bottom.', 'Maaari itong payagan ng Punong Barangay o ng Kalihim sa Mga widget, sa ibaba.') + '</span>' + (WS.S.lead ? A.btn(T('Allow minigames', 'Payagan ang mga minigame'), '', { a: id + ':allow', p: 1 }) : '') + '</div>';
      var top = (g.top[id] || []).slice(0, 3), mine = g.mine[id];
      return '<div class="wx-game" tabindex="-1">' + render(g) + '</div><div class="wx-board">' + (mine != null ? '<span class="wx-pill" style="--c:#FF9800">' + T('My best ', 'Pinakamataas ko ') + esc(fmt(id, mine)) + '</span>' : '') + top.map(function (t, i) { return '<span class="wx-top"><i>' + (i + 1) + '</i>' + esc(WS.name(t.name || '').split(' ')[0]) + ' <b>' + esc(fmt(id, t.best)) + '</b></span>'; }).join('') + '</div>';
    };
    var a0 = def.a; def.a = function (a, el, e, c) { if (a === 'allow') { WS.post({ action: 'settings', games_enabled: '1' }).then(function (r) { if (r.error) WS.toast(r.error, true); else { WS.S.st = Object.assign(WS.S.st || {}, r.settings); WS.refresh(); } }); return; } if (a0) a0(a, el, e, c); };
    W[id] = def;
  }
  var save = function (id, v) { return WS.score(id, v).then(function (r) { if (r && r.ok) { var g = ok(WS.group('games')); if (g) { var old = g.mine[id]; if (old == null || (LOW.indexOf(id) >= 0 ? v < old : v > old)) g.mine[id] = v; } } }); };
  var btnRow = function (b) { return '<div class="wx-row">' + b + '</div>'; };

  // ---- tic-tac-toe
  var tt = { b: ['', '', '', '', '', '', '', '', ''], w: '', wins: 0 }, LN = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]];
  var ttw = function (b, m) { return LN.some(function (l) { return b[l[0]] === m && b[l[1]] === m && b[l[2]] === m; }); };
  game('ttt', {
    r: function () { return '<div class="wx-twocol"><div class="wx-ttt">' + tt.b.map(function (c, i) { return '<button type="button" data-a="ttt:m" data-i="' + i + '"' + (c || tt.w ? ' disabled' : '') + ' class="' + (c === 'X' ? 'x' : c === 'O' ? 'o' : '') + '">' + c + '</button>'; }).join('') + '</div><div class="wx-card2"><b>' + (tt.w === 'X' ? T('You win!', 'Panalo ka!') : tt.w === 'O' ? T('The computer wins.', 'Nanalo ang computer.') : tt.w === 'D' ? T('A draw.', 'Tabla.') : T('You are X. Your move.', 'Ikaw si X. Ikaw na.')) + '</b><span class="wx-note">' + T('Wins this visit: ', 'Panalo ngayon: ') + tt.wins + '</span>' + btnRow(A.btn(T('New game', 'Bagong laro'), '', { a: 'ttt:new', p: 1 })) + '</div></div>'; },
    a: function (a, el) {
      if (a === 'new') { tt.b = ['', '', '', '', '', '', '', '', '']; tt.w = ''; return WS.rerender(); }
      var i = +el.dataset.i, b = tt.b; if (a !== 'm' || b[i] || tt.w) return; b[i] = 'X';
      if (ttw(b, 'X')) { tt.w = 'X'; tt.wins++; save('ttt', tt.wins); } else if (b.every(Boolean)) tt.w = 'D'; else {
        var pick = -1; ['O', 'X'].forEach(function (m) { if (pick < 0) LN.forEach(function (l) { var v = l.map(function (k) { return b[k]; }); if (pick < 0 && v.filter(function (x) { return x === m; }).length === 2 && v.indexOf('') >= 0) pick = l[v.indexOf('')]; }); });
        if (pick < 0) pick = !b[4] ? 4 : [0, 2, 6, 8, 1, 3, 5, 7].filter(function (k) { return !b[k]; })[0];
        b[pick] = 'O'; if (ttw(b, 'O')) tt.w = 'O'; else if (b.every(Boolean)) tt.w = 'D';
      }
      WS.rerender();
    }
  });

  // ---- memory match
  var mm = null, EM = ['🌧', '🔥', '🚨', '🏠', '🚑', '📻', '🔦', '🧯'];
  var mmNew = function () { var d = EM.concat(EM); for (var i = d.length - 1; i > 0; i--) { var j = rnd(i + 1), x = d[i]; d[i] = d[j]; d[j] = x; } mm = { d: d, open: [], found: [], moves: 0, lock: 0 }; };
  game('mem', {
    r: function () { if (!mm) mmNew(); return '<div class="wx-twocol"><div class="wx-mem">' + mm.d.map(function (c, i) { var up = mm.open.indexOf(i) >= 0 || mm.found.indexOf(i) >= 0; return '<button type="button" data-a="mem:f" data-i="' + i + '" class="' + (mm.found.indexOf(i) >= 0 ? 'hit' : up ? 'up' : '') + '" aria-label="' + (up ? c : T('card', 'baraha')) + '"><span>' + (up ? c : '') + '</span></button>'; }).join('') + '</div><div class="wx-card2"><b>' + (mm.found.length === 16 ? T('All pairs found!', 'Nahanap lahat ng pares!') : T('Find the pairs', 'Hanapin ang mga pares')) + '</b><span class="wx-note">' + T('Moves: ', 'Galaw: ') + mm.moves + ' · ' + T('pairs ', 'pares ') + mm.found.length / 2 + '/8</span>' + btnRow(A.btn(T('Shuffle', 'Haluin'), '', { a: 'mem:new', p: 1 })) + '</div></div>'; },
    a: function (a, el) {
      if (a === 'new') { mmNew(); return WS.rerender(); }
      var i = +el.dataset.i; if (a !== 'f' || mm.lock || mm.open.indexOf(i) >= 0 || mm.found.indexOf(i) >= 0) return;
      mm.open.push(i);
      if (mm.open.length === 2) { mm.moves++; if (mm.d[mm.open[0]] === mm.d[mm.open[1]]) { mm.found = mm.found.concat(mm.open); mm.open = []; if (mm.found.length === 16) save('mem', mm.moves); } else { mm.lock = 1; setTimeout(function () { mm.open = []; mm.lock = 0; if (WS.S.tab === 'mem') WS.rerender(); }, 650); } }
      WS.rerender();
    }
  });

  // ---- reaction time
  var rc = { s: 'idle', ms: 0 };
  game('react', {
    r: function () { var m = { idle: [T('Press to start', 'Pindutin para magsimula'), '#2D4FA8'], wait: [T('Wait for green…', 'Hintayin ang berde…'), L.urgent], go: [T('NOW!', 'NGAYON!'), L.ok], early: [T('Too early. Press to try again', 'Masyadong maaga. Pindutin muli'), '#8E9ABB'], done: [rc.ms + ' ms · ' + T('press to try again', 'pindutin muli'), '#2D4FA8'] }[rc.s]; return '<button type="button" class="wx-react" data-a="react:p" style="--c:' + m[1] + '"><b>' + esc(m[0]) + '</b>' + (rc.s === 'done' ? '<span>' + (rc.ms < 250 ? T('Lightning!', 'Kidlat!') : rc.ms < 350 ? T('Sharp.', 'Alerto.') : T('Time for coffee.', 'Oras na para sa kape.')) + '</span>' : '') + '</button>'; },
    a: function () { if (rc.s === 'idle' || rc.s === 'done' || rc.s === 'early') { rc.s = 'wait'; clearTimeout(rc.t); rc.t = setTimeout(function () { rc.s = 'go'; rc.t0 = performance.now(); if (WS.S.tab === 'react') WS.rerender(); }, 1300 + rnd(2200)); } else if (rc.s === 'wait') { clearTimeout(rc.t); rc.s = 'early'; } else if (rc.s === 'go') { rc.ms = Math.round(performance.now() - rc.t0); rc.s = 'done'; save('react', rc.ms); } WS.rerender(); }
  });

  // ---- whack-a-mole
  var wk = { i: 4, n: 0, t0: 0, ms: 0 };
  game('whack', {
    r: function () { var c = ''; for (var q = 0; q < 9; q++) c += '<button type="button" data-a="whack:h" data-i="' + q + '" class="' + (q === wk.i && wk.n < 10 ? 'up' : '') + '"><span>' + (q === wk.i && wk.n < 10 ? '🐹' : '') + '</span></button>'; return '<div class="wx-twocol"><div class="wx-whack">' + c + '</div><div class="wx-card2"><b>' + (wk.n >= 10 ? T('Done in ' + (wk.ms / 1000).toFixed(1) + ' s!', 'Tapos sa ' + (wk.ms / 1000).toFixed(1) + ' s!') : T('Hits: ', 'Tama: ') + wk.n + ' / 10') + '</b><span class="wx-note">' + T('The clock starts at your first hit.', 'Magsisimula ang oras sa unang tama.') + '</span>' + btnRow(A.btn(T('Again', 'Muli'), '', { a: 'whack:new', p: 1 })) + '</div></div>'; },
    a: function (a, el) { if (a === 'new') { wk = { i: 4, n: 0, t0: 0, ms: 0 }; return WS.rerender(); } if (wk.n >= 10) return; var i = +el.dataset.i; if (i !== wk.i) return; if (!wk.t0) wk.t0 = performance.now(); wk.n++; if (wk.n >= 10) { wk.ms = Math.round(performance.now() - wk.t0); save('whack', wk.ms); } else { var x; do { x = rnd(9); } while (x === wk.i); wk.i = x; } WS.rerender(); }
  });

  // ---- higher or lower, rock paper scissors
  var hl = { n: 1 + rnd(13), s: 0, best: 0, msg: '' };
  game('hl', {
    r: function () { return '<div class="wx-twocol"><div class="wx-pcard" aria-label="' + hl.n + '"><b>' + hl.n + '</b></div><div class="wx-card2"><b>' + T('Is the next card higher or lower?', 'Mas mataas o mas mababa ang susunod?') + '</b><span class="wx-note">' + T('Streak ', 'Sunod-sunod ') + hl.s + ' · ' + T('best ', 'pinakamataas ') + hl.best + (hl.msg ? ' · ' + esc(hl.msg) : '') + '</span><div class="wx-row"><button type="button" class="wx-btn is-pri" data-a="hl:u">' + WS.svg('up', 15, 2.4) + T('Higher', 'Mas mataas') + '</button><button type="button" class="wx-btn" data-a="hl:d">' + WS.svg('down', 15, 2.4) + T('Lower', 'Mas mababa') + '</button></div></div></div>'; },
    a: function (a) { var x = 1 + rnd(13), win = a === 'u' ? x >= hl.n : x <= hl.n; hl.msg = (win ? T('Right, it was ', 'Tama, ') : T('Wrong, it was ', 'Mali, ')) + x; if (win) { hl.s++; hl.best = Math.max(hl.best, hl.s); } else { if (hl.s > 0) save('hl', hl.s); hl.s = 0; } hl.n = x; WS.rerender(); }
  });
  var rp = { w: 0, l: 0, d: 0, last: '' };
  game('rps', {
    r: function () { return '<div class="wx-twocol"><div class="wx-row">' + [['✊', 'r', T('Rock', 'Bato')], ['✋', 'p', T('Paper', 'Papel')], ['✌️', 's', T('Scissors', 'Gunting')]].map(function (k) { return '<button type="button" class="wx-rps" data-a="rps:g" data-k="' + k[1] + '" aria-label="' + k[2] + '">' + k[0] + '</button>'; }).join('') + '</div><div class="wx-card2"><b>' + esc(rp.last || T('Pick one.', 'Pumili ng isa.')) + '</b>' + A.kv([[T('Won', 'Panalo'), rp.w], [T('Lost', 'Talo'), rp.l], [T('Drew', 'Tabla'), rp.d]]) + '</div></div>'; },
    a: function (a, el) { var me = el.dataset.k, cp = 'rps'[rnd(3)], nm = { r: T('rock', 'bato'), p: T('paper', 'papel'), s: T('scissors', 'gunting') }; if (me === cp) { rp.d++; rp.last = T('Both ' + nm[me] + ': a draw.', 'Parehong ' + nm[me] + ': tabla.'); } else if ((me === 'r' && cp === 's') || (me === 'p' && cp === 'r') || (me === 's' && cp === 'p')) { rp.w++; rp.last = T('You win: ' + nm[me] + ' beats ' + nm[cp] + '.', 'Panalo ka: tinalo ng ' + nm[me] + ' ang ' + nm[cp] + '.'); save('rps', rp.w); } else { rp.l++; rp.last = T('You lose: ' + nm[cp] + ' beats ' + nm[me] + '.', 'Talo ka: tinalo ng ' + nm[cp] + ' ang ' + nm[me] + '.'); } WS.rerender(); }
  });

  // ---- snake
  var sn = null, SZ = 18;
  game('snake', {
    r: function () { return '<div class="wx-twocol"><div class="wx-snakewrap"><canvas id="wx-sn" width="270" height="270" tabindex="0" aria-label="' + T('Snake: use the arrow keys or swipe', 'Snake: gamitin ang arrow keys o mag-swipe') + '"></canvas></div><div class="wx-card2"><b id="wx-sns">' + T('Score 0', 'Iskor 0') + '</b><span class="wx-note">' + T('Arrow keys, or the pad below. Eat the red dot.', 'Arrow keys, o ang pad sa ibaba. Kainin ang pulang tuldok.') + '</span><div class="wx-pad">' + [['u', '▲'], ['l', '◀'], ['d', '▼'], ['r', '▶']].map(function (k) { return '<button type="button" data-a="snake:d" data-k="' + k[0] + '" class="p' + k[0] + '" aria-label="' + k[0] + '">' + k[1] + '</button>'; }).join('') + '</div>' + btnRow(A.btn(T('New game', 'Bagong laro'), '', { a: 'snake:new', p: 1 })) + '</div></div>'; },
    i: function (pane) {
      var cv = pane.querySelector('#wx-sn'), cx = cv.getContext('2d'), cell = 270 / SZ, dark = document.documentElement.getAttribute('data-theme') === 'dark';
      var start = function () { sn = { b: [[9, 9], [8, 9], [7, 9]], d: [1, 0], q: [1, 0], f: null, s: 0, over: false }; food(); };
      var food = function () { do { sn.f = [rnd(SZ), rnd(SZ)]; } while (sn.b.some(function (p) { return p[0] === sn.f[0] && p[1] === sn.f[1]; })); };
      var draw = function () {
        cx.fillStyle = dark ? '#161b22' : '#EEF2F8'; cx.fillRect(0, 0, 270, 270);
        cx.fillStyle = dark ? 'rgba(255,255,255,.04)' : 'rgba(20,27,52,.05)'; for (var i = 0; i < SZ; i++) for (var j = 0; j < SZ; j++) if ((i + j) % 2) cx.fillRect(i * cell, j * cell, cell, cell);
        cx.fillStyle = '#E5383B'; cx.beginPath(); cx.arc((sn.f[0] + .5) * cell, (sn.f[1] + .5) * cell, cell * .36, 0, 7); cx.fill();
        sn.b.forEach(function (p, i) { cx.fillStyle = i ? 'hsl(' + (150 - Math.min(i, 30)) + ',62%,' + (46 + (i % 2) * 4) + '%)' : '#2E9E4F'; cx.beginPath(); cx.roundRect ? cx.roundRect(p[0] * cell + 1, p[1] * cell + 1, cell - 2, cell - 2, 5) : cx.rect(p[0] * cell + 1, p[1] * cell + 1, cell - 2, cell - 2); cx.fill(); });
        if (sn.over) { cx.fillStyle = 'rgba(14,20,40,.6)'; cx.fillRect(0, 0, 270, 270); cx.fillStyle = '#fff'; cx.font = '800 20px Urbanist,sans-serif'; cx.textAlign = 'center'; cx.fillText(T('Game over', 'Tapos na'), 135, 135); }
        var s = document.getElementById('wx-sns'); if (s) s.textContent = T('Score ', 'Iskor ') + sn.s;
      };
      var step = function () {
        if (sn.over) return; sn.d = sn.q; var h = [sn.b[0][0] + sn.d[0], sn.b[0][1] + sn.d[1]];
        if (h[0] < 0 || h[1] < 0 || h[0] >= SZ || h[1] >= SZ || sn.b.some(function (p) { return p[0] === h[0] && p[1] === h[1]; })) { sn.over = true; if (sn.s) save('snake', sn.s); draw(); return; }
        sn.b.unshift(h); if (h[0] === sn.f[0] && h[1] === sn.f[1]) { sn.s += 10; food(); } else sn.b.pop(); draw();
      };
      W.snake.go = function (k) { var D = { u: [0, -1], d: [0, 1], l: [-1, 0], r: [1, 0] }[k]; if (D && !(D[0] === -sn.d[0] && D[1] === -sn.d[1])) sn.q = D; };
      if (!sn || sn.over) start(); draw();
      var speed = 120; WS.timer(step, speed);
      cv.addEventListener('keydown', function (e) { var k = { ArrowUp: 'u', ArrowDown: 'd', ArrowLeft: 'l', ArrowRight: 'r', w: 'u', s: 'd', a: 'l', d: 'r' }[e.key]; if (k) { e.preventDefault(); W.snake.go(k); } });
      var sx, sy; cv.addEventListener('touchstart', function (e) { sx = e.touches[0].clientX; sy = e.touches[0].clientY; }, { passive: true }); cv.addEventListener('touchend', function (e) { var dx = e.changedTouches[0].clientX - sx, dy = e.changedTouches[0].clientY - sy; if (Math.max(Math.abs(dx), Math.abs(dy)) > 20) W.snake.go(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'r' : 'l') : (dy > 0 ? 'd' : 'u')); });
    },
    a: function (a, el) { if (a === 'd') W.snake.go(el.dataset.k); else if (a === 'new') { sn = null; WS.rerender(); } }
  });

  // ---- 2048
  var g4 = null;
  var g4new = function () { g4 = { g: [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], s: 0, over: false }; g4add(); g4add(); };
  var g4add = function () { var e = []; g4.g.forEach(function (r, y) { r.forEach(function (v, x) { if (!v) e.push([y, x]); }); }); if (e.length) { var p = e[rnd(e.length)]; g4.g[p[0]][p[1]] = Math.random() < .9 ? 2 : 4; } };
  var g4mv = function (d) {
    var g = g4.g, moved = false, rot = function (m) { return m[0].map(function (_, i) { return m.map(function (r) { return r[i]; }).reverse(); }); };
    var k = { l: 0, u: 3, r: 2, d: 1 }[d], m = g; for (var i = 0; i < k; i++) m = rot(m);
    m = m.map(function (r) { var a = r.filter(Boolean), o = []; for (var j = 0; j < a.length; j++) { if (a[j] === a[j + 1]) { o.push(a[j] * 2); g4.s += a[j] * 2; j++; } else o.push(a[j]); } while (o.length < 4) o.push(0); if (o.join() !== r.join()) moved = true; return o; });
    for (i = 0; i < (4 - k) % 4; i++) m = rot(m);
    if (moved) { g4.g = m; g4add(); var can = g4.g.some(function (r, y) { return r.some(function (v, x) { return !v || (g4.g[y][x + 1] === v) || (g4.g[y + 1] && g4.g[y + 1][x] === v); }); }); if (!can) { g4.over = true; save('g2048', g4.s); } }
  };
  game('g2048', {
    r: function () { if (!g4) g4new(); return '<div class="wx-twocol"><div class="wx-2048" tabindex="0" aria-label="2048: arrow keys or swipe">' + g4.g.map(function (r) { return r.map(function (v) { return '<i class="t' + (v > 2048 ? 'x' : v) + '">' + (v || '') + '</i>'; }).join(''); }).join('') + (g4.over ? '<div class="ov">' + T('Game over', 'Tapos na') + '</div>' : '') + '</div><div class="wx-card2"><b>' + T('Score ', 'Iskor ') + g4.s + '</b><span class="wx-note">' + T('Arrow keys or swipe. Merge equal tiles.', 'Arrow keys o swipe. Pagsamahin ang magkaparehong tile.') + '</span>' + btnRow(A.btn(T('New game', 'Bagong laro'), '', { a: 'g2048:new', p: 1 })) + '</div></div>'; },
    i: function (pane) { var b = pane.querySelector('.wx-2048'), go = function (d) { if (!g4.over) { g4mv(d); WS.rerender(); var q = document.querySelector('.wx-2048'); if (q) q.focus(); } }; b.addEventListener('keydown', function (e) { var d = { ArrowLeft: 'l', ArrowRight: 'r', ArrowUp: 'u', ArrowDown: 'd' }[e.key]; if (d) { e.preventDefault(); go(d); } }); var sx, sy; b.addEventListener('touchstart', function (e) { sx = e.touches[0].clientX; sy = e.touches[0].clientY; }, { passive: true }); b.addEventListener('touchend', function (e) { var dx = e.changedTouches[0].clientX - sx, dy = e.changedTouches[0].clientY - sy; if (Math.max(Math.abs(dx), Math.abs(dy)) > 24) go(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'r' : 'l') : (dy > 0 ? 'd' : 'u')); }); },
    a: function (a) { if (a === 'new') { g4new(); WS.rerender(); } }
  });

  // ---- Hulaan: five letters, six tries, the same word for everyone today
  var HW = ['BAHAY', 'KAMAY', 'TUBIG', 'BAYAN', 'GABAY', 'LABAN', 'LAKAD', 'MUKHA', 'SULAT', 'HAPON', 'UMAGA', 'BULAN', 'KALYE', 'DAGAT', 'BUHAY', 'LUNAS', 'HIRAP', 'TAPAT', 'PULIS', 'SAKIT', 'PINTO', 'BAKOD', 'GAMOT', 'LUTAS', 'SAGOT', 'TANOD', 'RONDA', 'HAWAK', 'SABAY', 'TAWAG', 'BATAS', 'KORTE', 'BAYAD', 'AYUDA', 'PASOK', 'TULAY', 'HUKOM', 'LIGAW', 'KAPIT'];
  var hu = null;
  var huLoad = function () { var s = WS.mine.get('hulaan', null), w = HW[day() % HW.length]; hu = s && s.d === today() ? s : { d: today(), g: [], cur: '' }; hu.w = w; hu.cur = hu.cur || ''; };
  var huRow = function (gs, w) { var r = [], cnt = {}; for (var i = 0; i < 5; i++) if (gs[i] !== w[i]) cnt[w[i]] = (cnt[w[i]] || 0) + 1; for (i = 0; i < 5; i++) { if (gs[i] === w[i]) r[i] = 'g'; else if (cnt[gs[i]] > 0) { r[i] = 'y'; cnt[gs[i]]--; } else r[i] = 'x'; } return r; };
  game('wordl', {
    r: function () { if (!hu || hu.d !== today()) huLoad(); var done = hu.g.length && hu.g[hu.g.length - 1] === hu.w, fail = !done && hu.g.length >= 6, kc = {}; hu.g.forEach(function (g) { huRow(g, hu.w).forEach(function (c, i) { var k = g[i]; if (c === 'g' || (c === 'y' && kc[k] !== 'g') || !kc[k]) kc[k] = c; }); });
      var rows = ''; for (var y = 0; y < 6; y++) { var g = hu.g[y], cur = y === hu.g.length && !done ? hu.cur : '', rr = g ? huRow(g, hu.w) : []; rows += '<div class="r">' + [0, 1, 2, 3, 4].map(function (x) { return '<i class="' + (g ? rr[x] : cur[x] ? 'f' : '') + '" style="--d:' + x * 90 + 'ms">' + (g ? g[x] : cur[x] || '') + '</i>'; }).join('') + '</div>'; }
      return '<div class="wx-hulaan" tabindex="0" aria-label="' + T('Hulaan: type a five-letter word', 'Hulaan: mag-type ng limang-titik na salita') + '">' + rows + '<div class="kb">' + ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'].map(function (r, i) { return '<div>' + (i === 2 ? '<button type="button" data-a="wordl:k" data-k="⏎" class="w">⏎</button>' : '') + r.split('').map(function (k) { return '<button type="button" data-a="wordl:k" data-k="' + k + '" class="' + (kc[k] || '') + '">' + k + '</button>'; }).join('') + (i === 2 ? '<button type="button" data-a="wordl:k" data-k="⌫" class="w">⌫</button>' : '') + '</div>'; }).join('') + '</div></div><p class="wx-note">' + (done ? T('Solved in ' + hu.g.length + '! A new word tomorrow.', 'Nalutas sa ' + hu.g.length + '! Bagong salita bukas.') : fail ? T('The word was ', 'Ang salita ay ') + hu.w + '.' : T('Everyone has the same Filipino word today. Green is right, yellow is in the word, grey is not.', 'Iisang salitang Filipino ang lahat ngayon. Berde ay tama, dilaw ay nasa salita, abo ay wala.')) + '</p>'; },
    a: function (a, el) { W.wordl.key(el.dataset.k); },
    key: function (k) { if (!hu) huLoad(); if (hu.g.length && hu.g[hu.g.length - 1] === hu.w || hu.g.length >= 6) return; if (k === '⌫') hu.cur = hu.cur.slice(0, -1); else if (k === '⏎') { if (hu.cur.length < 5) return WS.toast(T('Five letters, please.', 'Limang titik po.'), true); hu.g.push(hu.cur); hu.cur = ''; if (hu.g[hu.g.length - 1] === hu.w) save('wordl', hu.g.length); WS.mine.set('hulaan', { d: hu.d, g: hu.g, cur: '' }); } else if (/^[A-Z]$/.test(k) && hu.cur.length < 5) hu.cur += k; WS.rerender(); var q = document.querySelector('.wx-hulaan'); if (q) q.focus(); },
    i: function (pane) { var q = pane.querySelector('.wx-hulaan'); q.addEventListener('keydown', function (e) { if (e.ctrlKey || e.metaKey || e.altKey) return; var k = e.key === 'Enter' ? '⏎' : e.key === 'Backspace' ? '⌫' : e.key.toUpperCase(); if (/^[A-Z]$|^[⏎⌫]$/.test(k) && e.key.length <= 9) { e.preventDefault(); W.wordl.key(k); } }); }
  });

  // ---- sudoku
  var sd = null;
  function sdGen() {
    var g = [], i; for (i = 0; i < 81; i++) g.push(0);
    var ok2 = function (g, p, v) { var r = Math.floor(p / 9), c = p % 9; for (var k = 0; k < 9; k++) { if (g[r * 9 + k] === v || g[k * 9 + c] === v) return false; } var br = r - r % 3, bc = c - c % 3; for (var y = 0; y < 3; y++) for (var x = 0; x < 3; x++) if (g[(br + y) * 9 + bc + x] === v) return false; return true; };
    var solve = function (g) { var p = g.indexOf(0); if (p < 0) return true; var o = [1, 2, 3, 4, 5, 6, 7, 8, 9].sort(function () { return Math.random() - .5; }); for (var k = 0; k < 9; k++) if (ok2(g, p, o[k])) { g[p] = o[k]; if (solve(g)) return true; g[p] = 0; } return false; };
    solve(g); var sol = g.slice(), pz = g.slice(), idx = []; for (i = 0; i < 81; i++) idx.push(i); idx.sort(function () { return Math.random() - .5; }); idx.slice(0, 42).forEach(function (p) { pz[p] = 0; });
    return { sol: sol, p: pz, g: pz.slice(), sel: -1, t0: 0, ms: 0, done: false, fixed: pz.map(function (v) { return v > 0; }) };
  }
  game('sudoku', {
    r: function () { if (!sd) sd = sdGen(); var bad = function (p) { var v = sd.g[p]; if (!v || sd.fixed[p]) return false; return v !== sd.sol[p]; }; var cells = sd.g.map(function (v, p) { var r = Math.floor(p / 9), c = p % 9; return '<button type="button" data-a="sudoku:s" data-i="' + p + '" class="' + (sd.fixed[p] ? 'fx ' : '') + (p === sd.sel ? 'sel ' : '') + (sd.sel >= 0 && v && sd.g[sd.sel] === v ? 'same ' : '') + (bad(p) && sd.chk ? 'bad ' : '') + (c % 3 === 2 && c < 8 ? 'rr ' : '') + (r % 3 === 2 && r < 8 ? 'rb' : '') + '" aria-label="' + (v || T('empty', 'walang laman')) + '">' + (v || '') + '</button>'; }).join(''); return '<div class="wx-twocol"><div class="wx-sudoku">' + cells + '</div><div class="wx-card2"><b id="wx-sdt">' + (sd.done ? T('Solved in ' + sd.ms + ' s!', 'Nalutas sa ' + sd.ms + ' s!') : '0 s') + '</b><div class="wx-numpad">' + [1, 2, 3, 4, 5, 6, 7, 8, 9].map(function (k) { return '<button type="button" data-a="sudoku:n" data-k="' + k + '">' + k + '</button>'; }).join('') + '<button type="button" data-a="sudoku:n" data-k="0" class="e">⌫</button></div><div class="wx-row">' + A.btn(T('Check', 'Suriin'), '', { a: 'sudoku:chk' }) + A.btn(T('New puzzle', 'Bagong puzzle'), '', { a: 'sudoku:new', p: 1 }) + '</div></div></div>'; },
    i: function () { if (sd && !sd.done) WS.timer(function () { var e = document.getElementById('wx-sdt'); if (e && sd.t0) e.textContent = Math.round((Date.now() - sd.t0) / 1000) + ' s'; }, 1000); },
    a: function (a, el) {
      if (a === 'new') { sd = sdGen(); return WS.rerender(); } if (a === 'chk') { sd.chk = 1; return WS.rerender(); }
      if (a === 's') { sd.sel = +el.dataset.i; return WS.rerender(); }
      if (a === 'n' && sd.sel >= 0 && !sd.fixed[sd.sel] && !sd.done) { if (!sd.t0) sd.t0 = Date.now(); sd.g[sd.sel] = +el.dataset.k; sd.chk = 0; if (sd.g.every(function (v, i) { return v === sd.sol[i]; })) { sd.done = true; sd.ms = Math.round((Date.now() - sd.t0) / 1000); save('sudoku', sd.ms); } WS.rerender(); }
    }
  });

  // ---- minesweeper
  var ms = null, MW = 9, MN = 10;
  var msNew = function () { ms = { m: null, o: [], f: [], over: 0, win: 0, t0: 0, ms: 0, flag: 0 }; for (var i = 0; i < 81; i++) { ms.o.push(0); ms.f.push(0); } };
  var msAdj = function (p) { var r = Math.floor(p / 9), c = p % 9, o = []; for (var y = -1; y <= 1; y++) for (var x = -1; x <= 1; x++) { var a = r + y, b = c + x; if ((y || x) && a >= 0 && b >= 0 && a < MW && b < MW) o.push(a * 9 + b); } return o; };
  var msOpen = function (p) { if (ms.o[p] || ms.f[p]) return; ms.o[p] = 1; if (ms.m[p]) { ms.over = 1; return; } var c = msAdj(p).filter(function (q) { return ms.m[q]; }).length; if (!c) msAdj(p).forEach(msOpen); };
  game('mines', {
    r: function () { if (!ms) msNew(); var cells = ms.o.map(function (o, p) { var c = ms.m ? msAdj(p).filter(function (q) { return ms.m[q]; }).length : 0, mine = ms.m && ms.m[p]; return '<button type="button" data-a="mines:c" data-i="' + p + '" class="' + (o ? 'o n' + c : '') + (ms.over && mine ? ' bomb' : '') + '" aria-label="' + (o ? c : ms.f[p] ? T('flag', 'bandila') : T('hidden', 'nakatago')) + '">' + (ms.over && mine ? '💣' : o ? (c || '') : ms.f[p] ? '🚩' : '') + '</button>'; }).join(''); return '<div class="wx-twocol"><div class="wx-mines">' + cells + '</div><div class="wx-card2"><b>' + (ms.win ? T('Cleared in ' + ms.ms + ' s!', 'Nalinis sa ' + ms.ms + ' s!') : ms.over ? T('Boom. Try again.', 'Sumabog. Subukan muli.') : T('Mines left: ', 'Natitirang mina: ') + (MN - ms.f.filter(Boolean).length)) + '</b><span class="wx-note">' + T('Tap to open. Switch to flag mode, or right-click, to mark a mine.', 'Pindutin para buksan. Lumipat sa flag mode, o right-click, para markahan ang mina.') + '</span><div class="wx-row"><button type="button" class="wx-btn' + (ms.flag ? ' is-pri' : '') + '" data-a="mines:fl" aria-pressed="' + !!ms.flag + '">🚩 ' + T('Flag mode', 'Flag mode') + '</button>' + A.btn(T('New game', 'Bagong laro'), '', { a: 'mines:new', p: 1 }) + '</div></div></div>'; },
    i: function (pane) { pane.querySelector('.wx-mines').addEventListener('contextmenu', function (e) { var b = e.target.closest('[data-i]'); if (b) { e.preventDefault(); W.mines.a('fg', b); } }); },
    a: function (a, el) {
      if (a === 'new') { msNew(); return WS.rerender(); } if (a === 'fl') { ms.flag = !ms.flag; return WS.rerender(); }
      if (ms.over || ms.win) return; var p = +el.dataset.i;
      if (a === 'fg' || (a === 'c' && ms.flag)) { if (!ms.o[p]) ms.f[p] = ms.f[p] ? 0 : 1; return WS.rerender(); }
      if (a !== 'c') return;
      if (!ms.m) { var s = [], q; for (q = 0; q < 81; q++) if (q !== p && msAdj(p).indexOf(q) < 0) s.push(q); s.sort(function () { return Math.random() - .5; }); ms.m = []; for (q = 0; q < 81; q++) ms.m.push(0); s.slice(0, MN).forEach(function (x) { ms.m[x] = 1; }); ms.t0 = Date.now(); }
      msOpen(p); if (!ms.over && ms.o.filter(Boolean).length === 81 - MN) { ms.win = 1; ms.ms = Math.round((Date.now() - ms.t0) / 1000); save('mines', ms.ms); } WS.rerender();
    }
  });

  // ---- the barangay quiz
  var QZ = [[T('How many days does the Punong Barangay have to mediate a complaint?', 'Ilang araw ang mayroon ang Punong Barangay para mamagitan sa reklamo?'), ['15', '30', '7', '60'], 0], [T('Who mediates when the Punong Barangay cannot settle it?', 'Sino ang namamagitan kapag hindi naareglo ng Punong Barangay?'), ['Pangkat ng Tagapagkasundo', 'The Sanggunian', 'The police', 'The court'], 0], [T('What lets a complainant go to court after mediation fails?', 'Ano ang nagpapahintulot na magsampa sa korte kapag nabigo ang pamamagitan?'), [T('A certificate to file action', 'Sertipiko para magsampa ng kaso'), T('A barangay clearance', 'Barangay clearance'), T('A cedula', 'Cedula'), T('A police blotter', 'Police blotter')], 0], [T('What is the national emergency hotline?', 'Ano ang pambansang hotline sa emergency?'), ['911', '117', '143', '8888'], 0], [T('Which law is the Local Government Code?', 'Anong batas ang Local Government Code?'), ['RA 7160', 'RA 9262', 'RA 10121', 'RA 6713'], 0], [T('First step for heat stroke?', 'Unang hakbang sa heat stroke?'), [T('Move to shade and cool the body', 'Ilipat sa lilim at palamigin ang katawan'), T('Give hot tea', 'Painumin ng mainit na tsaa'), T('Wrap in a blanket', 'Balutin ng kumot'), T('Wait and watch', 'Maghintay at magmasid')], 0], [T('How long do you cool a burn under running water?', 'Gaano katagal palamigin ang paso sa umaagos na tubig?'), [T('20 minutes', '20 minuto'), T('1 minute', '1 minuto'), T('2 hours', '2 oras'), T('Not at all', 'Hindi na')], 0], [T('Reports of violence against a woman should be…', 'Ang ulat ng karahasan laban sa babae ay dapat…'), [T('Passed up at once, with the hotlines', 'Iakyat agad, kasama ang mga hotline'), T('Mediated like any dispute', 'Idaan sa pamamagitan tulad ng ibang alitan'), T('Closed quietly', 'Tahimik na isara'), T('Left for next week', 'Iwan hanggang susunod na linggo')], 0], [T('What is the highest wind signal in the Philippines?', 'Ano ang pinakamataas na signal ng hangin sa Pilipinas?'), ['5', '3', '4', '10'], 0], [T('What does a Red rainfall warning mean?', 'Ano ang ibig sabihin ng Pulang babala sa ulan?'), [T('Serious flooding is expected', 'Inaasahan ang malubhang baha'), T('Light rain', 'Mahinang ulan'), T('Rain has ended', 'Tapos na ang ulan'), T('Only a drizzle', 'Ambon lamang')], 0], [T('CPR chest presses per minute?', 'Ilang pindot sa dibdib bawat minuto sa CPR?'), ['100 to 120', '40 to 60', '200 to 240', '10 to 20'], 0], [T('How many presses before 2 breaths in CPR?', 'Ilang pindot bago ang 2 hinga sa CPR?'), ['30', '5', '15', '60'], 0], [T('What does NOAH stand for?', 'Ano ang ibig sabihin ng NOAH?'), ['Nationwide Operational Assessment of Hazards', 'National Office of Aid and Help', 'Natural Outbreak Alert Hub', 'Northern Ocean and Air Hub'], 0], [T('Who is the chief executive of the barangay?', 'Sino ang punong ehekutibo ng barangay?'), ['Punong Barangay', 'Kagawad', 'Secretary', 'Tanod'], 0], [T('A choking adult can still cough. What now?', 'Nakaubo pa ang nabubulunan. Ano ang gagawin?'), [T('Encourage coughing', 'Himukin ang pag-ubo'), T('Slap hard at once', 'Palakpakan agad nang malakas'), T('Give water', 'Painumin ng tubig'), T('Lay them flat', 'Ihiga nang patag')], 0]];
  var qz = null;
  var qzNew = function () { var o = QZ.map(function (q, i) { return i; }).sort(function () { return Math.random() - .5; }).slice(0, 10); qz = { o: o, i: 0, s: 0, ans: -1, sh: null }; qzSh(); };
  var qzSh = function () { var q = QZ[qz.o[qz.i]]; qz.sh = q[1].map(function (_, i) { return i; }).sort(function () { return Math.random() - .5; }); };
  game('quiz', {
    r: function () { if (!qz) qzNew(); if (qz.i >= 10) return '<div class="wx-card2" style="place-items:center;text-align:center"><div class="wx-big" style="justify-items:center"><b>' + qz.s + '/10</b><span>' + (qz.s >= 9 ? T('Barangay expert!', 'Eksperto sa barangay!') : qz.s >= 6 ? T('Well done.', 'Magaling.') : T('Keep learning.', 'Magpatuloy sa pag-aaral.')) + '</span></div>' + btnRow(A.btn(T('Play again', 'Maglaro muli'), '', { a: 'quiz:new', p: 1 })) + '</div>'; var q = QZ[qz.o[qz.i]]; return '<div class="wx-card2"><span class="wx-h">' + T('Question ', 'Tanong ') + (qz.i + 1) + ' / 10 · ' + T('score ', 'iskor ') + qz.s + '</span>' + A.bar((qz.i) * 10, '#FF9800', 6) + '<b style="font:800 16px/1.35 Urbanist">' + esc(q[0]) + '</b><div class="wx-answers">' + qz.sh.map(function (k) { var st = qz.ans < 0 ? '' : k === q[2] ? ' ok' : k === qz.ans ? ' no' : ''; return '<button type="button" class="wx-ans' + st + '" data-a="quiz:a" data-k="' + k + '"' + (qz.ans >= 0 ? ' disabled' : '') + '>' + esc(q[1][k]) + '</button>'; }).join('') + '</div>' + (qz.ans >= 0 ? btnRow(A.btn(qz.i === 9 ? T('See my score', 'Tingnan ang iskor ko') : T('Next', 'Susunod'), '', { a: 'quiz:next', p: 1 })) : '') + '</div>'; },
    a: function (a, el) { if (a === 'new') { qzNew(); return WS.rerender(); } if (a === 'a') { qz.ans = +el.dataset.k; if (qz.ans === QZ[qz.o[qz.i]][2]) qz.s++; return WS.rerender(); } if (a === 'next') { qz.i++; qz.ans = -1; if (qz.i >= 10) save('quiz', qz.s); else qzSh(); WS.rerender(); } }
  });

  // ---- Simon
  var sm = { seq: [], at: 0, show: 0, on: false, lit: -1 }, FQ = [262, 330, 392, 523];
  game('simon', {
    r: function () { return '<div class="wx-twocol"><div class="wx-simon">' + ['g', 'r', 'y', 'b'].map(function (c, i) { return '<button type="button" data-a="simon:p" data-i="' + i + '" class="' + c + (sm.lit === i ? ' lit' : '') + '" aria-label="' + c + '"' + (sm.show || !sm.on ? ' disabled' : '') + '></button>'; }).join('') + '</div><div class="wx-card2"><b>' + (sm.on ? (sm.show ? T('Watch…', 'Panoorin…') : T('Your turn', 'Ikaw na')) : sm.seq.length ? T('Game over: round ', 'Tapos na: round ') + (sm.seq.length - 1) : T('Repeat the colours', 'Ulitin ang mga kulay')) + '</b><span class="wx-note">' + T('Round ', 'Round ') + Math.max(0, sm.seq.length - (sm.on ? 0 : 1)) + '</span>' + btnRow(A.btn(T('Start', 'Simulan'), '', { a: 'simon:go', p: 1 })) + '</div></div>'; },
    a: function (a, el) {
      var tone = function (i) { try { var c = W.simon.ctx || (W.simon.ctx = new (window.AudioContext || window.webkitAudioContext)()), o = c.createOscillator(), g = c.createGain(); o.frequency.value = FQ[i]; g.gain.value = .07; o.connect(g); g.connect(c.destination); o.start(); o.stop(c.currentTime + .22); } catch (e) {} };
      var flash = function (i, cb) { sm.lit = i; tone(i); WS.rerender(); setTimeout(function () { sm.lit = -1; if (WS.S.tab === 'simon') WS.rerender(); if (cb) setTimeout(cb, 130); }, 380); };
      var play = function () { sm.show = 1; sm.at = 0; WS.rerender(); var k = 0, next = function () { if (WS.S.tab !== 'simon') return; if (k >= sm.seq.length) { sm.show = 0; sm.at = 0; WS.rerender(); return; } flash(sm.seq[k++], next); }; setTimeout(next, 500); };
      if (a === 'go') { sm = { seq: [rnd(4)], at: 0, show: 0, on: true, lit: -1 }; return play(); }
      if (a === 'p' && sm.on && !sm.show) { var i = +el.dataset.i; if (sm.seq[sm.at] !== i) { sm.on = false; tone(0); save('simon', sm.seq.length - 1); return WS.rerender(); } sm.at++; if (sm.at >= sm.seq.length) { sm.seq.push(rnd(4)); setTimeout(play, 600); sm.show = 1; } flash(i); }
    }
  });

  // ---- typing speed
  var TY = [T('The tanod arrived at the corner and found the road blocked by a fallen tree.', 'Dumating ang tanod sa kanto at nakitang hinarangan ng natumbang puno ang daan.'), 'The resident reported loud music near the market after ten o\'clock at night.', 'Please send a clearer photo of the street so the team can find the place faster.', 'The case was resolved and the family was told the same afternoon.', 'Two stray dogs were seen near the school gate early in the morning.', 'The drainage on the corner is clogged again and water is rising on the road.'];
  var ty = { s: TY[0], t0: 0, v: '', done: 0, wpm: 0, acc: 100 };
  game('type', {
    r: function () { var s = ty.s, v = ty.v; return '<div class="wx-type"><div class="tx" aria-label="' + esc(s) + '">' + s.split('').map(function (c, i) { return '<i class="' + (i < v.length ? (v[i] === c ? 'ok' : 'no') : i === v.length ? 'cur' : '') + '">' + esc(c) + '</i>'; }).join('') + '</div><input id="wx-ti" class="wx-tin" data-i="type:in" autocomplete="off" autocapitalize="off" spellcheck="false" ' + (ty.done ? 'disabled' : '') + ' value="' + esc(v) + '" placeholder="' + T('Start typing here', 'Mag-type dito') + '" aria-label="' + T('Type the sentence', 'I-type ang pangungusap') + '"></div><div class="wx-row">' + (ty.done ? A.big(ty.wpm, 'wpm', '#2E9E4F') + A.big(ty.acc + '%', T('accuracy', 'katumpakan'), '#356CF9') : '<span class="wx-note">' + T('The clock starts with your first key.', 'Magsisimula ang oras sa unang pindot.') + '</span>') + A.btn(T('New sentence', 'Bagong pangungusap'), '', { a: 'type:new', p: 1 }) + '</div>'; },
    i: function () { var e = document.getElementById('wx-ti'); if (e && !ty.done) { e.focus(); e.setSelectionRange(e.value.length, e.value.length); } },
    n: function (a, el) { if (ty.done) return; if (!ty.t0) ty.t0 = Date.now(); ty.v = el.value.slice(0, ty.s.length); var s = ty.s, v = ty.v, err = 0; for (var i = 0; i < v.length; i++) if (v[i] !== s[i]) err++; var box = document.querySelector('.wx-type .tx'); if (box) Array.prototype.forEach.call(box.children, function (c, i) { c.className = i < v.length ? (v[i] === s[i] ? 'ok' : 'no') : i === v.length ? 'cur' : ''; }); if (v.length === s.length) { var min = (Date.now() - ty.t0) / 60000; ty.wpm = Math.round(s.length / 5 / min); ty.acc = Math.round((s.length - err) / s.length * 100); ty.done = 1; if (ty.acc >= 90) save('type', ty.wpm); WS.rerender(); } },
    a: function (a) { if (a === 'new') { ty = { s: TY[rnd(TY.length)], t0: 0, v: '', done: 0, wpm: 0, acc: 100 }; WS.rerender(); } }
  });
})();
