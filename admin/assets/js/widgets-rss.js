// Workspace widgets: news and RSS (17 Oct 2026). Headlines, fuel prices, water and power notices, the disaster and health
// feeds, and a person's own feeds and watch words. Every feed is read by the portal (widgets.php), never by the
// browser, and news searches say so: they are stories that mention a subject, not official notices.
(function () {
  var WS = window.WS, T = WS.T, A = WS.a, esc = WS.esc, n = WS.n, W = WS.w, L = WS.lvl;
  var ok = function (g) { return g && g.ok ? g.data : null; };
  var field = function (label, html) { return '<label class="wx-f"><span>' + label + '</span>' + html + '</label>'; };
  var done = function (msg) { return function (r) { if (r && r.error) { WS.toast(r.error, true); return false; } if (msg) WS.toast(msg); WS.refresh(); return true; }; };
  var host = function (u) { try { return new URL(u).hostname.replace(/^www\./, ''); } catch (e) { return ''; } };
  var mark = function (s, words) { s = esc(s); (words || []).forEach(function (w) { if (!w) return; var re = new RegExp('(' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig'); s = s.replace(re, '<mark>$1</mark>'); }); return s; };

  // one story card
  function story(x, o) {
    o = o || {}; var l = WS.link(x.link), tag = l ? 'a' : 'div', c = o.c || '#356CF9';
    var pub = x.src || x.feed || '';
    return '<' + tag + ' class="wx-story' + (x.match && x.match.length ? ' is-hit' : '') + '"' + (l ? ' href="' + esc(l) + '" target="_blank" rel="noopener noreferrer"' : '') + ' style="--c:' + c + '">' + (o.lead ? '<span class="lead">' + o.lead + '</span>' : '') + '<b>' + mark(x.t, x.match || o.words) + '</b>' + (x.sum && !o.nosum ? '<p>' + esc(x.sum) + '</p>' : '') + '<small>' + (pub ? esc(pub) + ' · ' : '') + (x.at ? esc(WS.ago(x.at)) : '') + (x.match && x.match.length ? ' · ' + A.pill(x.match.map(esc).join(', '), '#FFB000') : '') + '</small></' + tag + '>';
  }
  var stories = function (items, o) { return items.length ? '<div class="wx-stories">' + items.map(function (x) { return story(x, o); }).join('') + '</div>' : A.empty('news', T('Nothing new in this feed', 'Walang bago sa feed na ito')); };
  var viaNote = function () { return '<p class="wx-note">' + T('News stories from a search, with the publisher named. Not an official notice: confirm with the utility or the city.', 'Mga balita mula sa paghahanap, may pangalan ng naglathala. Hindi opisyal na abiso: kumpirmahin sa utility o sa lungsod.') + '</p>'; };
  var feedOf = function (key) { return ok(WS.group('rss:' + key)); };
  var head = function (d, extra) { return '<div class="wx-row"><b style="font:800 15px Urbanist">' + esc(d.name) + '</b>' + (d.search ? A.pill(T('via Google News', 'sa pamamagitan ng Google News'), L.low) : '') + '<span class="wx-note" style="margin-left:auto">' + d.items.length + ' ' + T('stories', 'balita') + '</span></div>' + (extra || ''); };

  function simple(id, key, opts) {
    opts = opts || {};
    W[id] = { r: function () { var d = feedOf(key); return head(d) + stories(d.items.slice(0, opts.max || 6), opts) + (d.search ? viaNote() : ''); }, src: opts.src || '' };
  }
  simple('rsswater', 'water', { c: '#2D7DD2', src: 'Google News (Maynilad)' });
  simple('rsspower', 'power', { c: '#F5A524', src: 'Google News (Meralco)' });
  simple('rssphilstar', 'philstar', { src: 'Philstar' });
  simple('rssrappler', 'rappler', { src: 'Rappler' });
  simple('rssgma', 'gma', { src: 'GMA News' });
  simple('rsswho', 'who', { c: '#00A5B5', src: 'WHO' });

  W.rssgdacs = {
    r: function () {
      var d = feedOf('gdacs'), col = function (t) { return /red/i.test(t) ? L.urgent : /orange/i.test(t) ? L.high : /green/i.test(t) ? L.ok : L.low; };
      var its = d.items.slice(0, 6).map(function (x) { var c = col(x.t); return x; });
      return head(d) + '<div class="wx-stories">' + its.map(function (x) { return story(x, { c: col(x.t), lead: A.pill((x.t.match(/(red|orange|green)/i) || ['', T('alert', 'alerto')])[1].toUpperCase(), col(x.t)) }); }).join('') + '</div><p class="wx-note">' + T('Global Disaster Alert and Coordination System, worldwide; the storms near the Philippines are in Typhoon watch.', 'Pandaigdigang sistema ng alerto sa sakuna; ang mga bagyo malapit sa Pilipinas ay nasa Bantay-bagyo.') + '</p>';
    }, src: 'GDACS'
  };
  W.rssusgs = {
    r: function () {
      var d = feedOf('usgs'), mag = function (t) { var m = /^M\s*([0-9.]+)/.exec(t); return m ? +m[1] : 0; }, col = function (m) { return m >= 6 ? '#8E3FD0' : m >= 5 ? L.urgent : L.high; };
      return head(d) + '<div class="wx-stories">' + d.items.slice(0, 7).map(function (x) { var m = mag(x.t); return story(x, { c: col(m), nosum: 1, lead: '<span class="wx-mag" style="--c:' + col(m) + '">' + (m ? m.toFixed(1) : '·') + '</span>' }); }).join('') + '</div><p class="wx-note">' + T('Magnitude 4.5 and up anywhere in the world this week. Quakes near Luzon are in the Earthquakes widget.', 'Magnitude 4.5 pataas saanman sa mundo ngayong linggo. Ang lindol malapit sa Luzon ay nasa widget na Lindol.') + '</p>';
    }, src: 'USGS'
  };
  W.fuel = {
    r: function () {
      var d = feedOf('fuel'), dir = function (t) { return /rollback|cut|decrease|lower|bawas|ibaba/i.test(t) && /hike|increase|rise|dagdag/i.test(t) ? 0 : /rollback|cut|decrease|lower/i.test(t) ? -1 : /hike|increase|rise/i.test(t) ? 1 : 0; };
      var first = d.items[0], k = first ? dir(first.t) : 0;
      return (first ? '<div class="wx-hero" style="--hg:linear-gradient(135deg,#3B2A12,#C2410C);--hc:#FF9800"><span class="eb">' + T('Pump prices, next week', 'Presyo ng gasolina, susunod na linggo') + '</span><div class="hb" style="font-size:22px;line-height:1.25">' + esc(first.t.replace(/ - [^-]+$/, '')) + '</div><p class="hs">' + esc(first.src || '') + (first.at ? ' · ' + esc(WS.ago(first.at)) : '') + '</p></div>' : '') +
        stories(d.items.slice(1, 6), { c: '#FF9800', nosum: 1, lead: '' }).replace(/<span class="lead"><\/span>/g, '') + viaNote();
    }, src: 'Google News (oil prices)'
  };
  W.news = {
    r: function () {
      var keys = ['philstar', 'rappler', 'gma', 'inquirer'], f = W.news.f || '', all = [];
      keys.forEach(function (k) { var d = feedOf(k); if (d) d.items.slice(0, 8).forEach(function (x) { all.push(Object.assign({ feed: d.name, k: k }, x)); }); });
      all.sort(function (a, b) { return String(b.at || '').localeCompare(String(a.at || '')); });
      var shown = all.filter(function (x) { return !f || x.k === f; }).slice(0, 7);
      return '<div class="wx-gtabs wx-inl" role="group" aria-label="' + T('Source', 'Pinagmulan') + '"><button type="button" data-a="news:f" data-k="" aria-pressed="' + !f + '">' + T('All', 'Lahat') + '</button>' + keys.map(function (k) { var d = feedOf(k); return d ? '<button type="button" data-a="news:f" data-k="' + k + '" aria-pressed="' + (f === k) + '">' + esc(d.name) + '</button>' : ''; }).join('') + '</div>' + stories(shown, { nosum: 0 });
    },
    a: function (a, el) { W.news.f = el.dataset.k; WS.rerender(); }, src: 'Philstar · Rappler · GMA · Inquirer'
  };
  W.rsspna = {
    r: function () {
      var keys = ['pna', 'inquirer', 'doh'], all = [];
      keys.forEach(function (k) { var d = feedOf(k); if (d) d.items.slice(0, 6).forEach(function (x) { all.push(Object.assign({ feed: d.name }, x)); }); });
      all.sort(function (a, b) { return String(b.at || '').localeCompare(String(a.at || '')); });
      return '<div class="wx-row"><b style="font:800 15px Urbanist">PNA · Inquirer · DOH</b>' + A.pill(T('PNA and DOH via news search', 'PNA at DOH sa pamamagitan ng paghahanap'), L.low) + '</div>' + stories(all.slice(0, 7)) + '<p class="wx-note">' + T('PNA publishes no feed and the DOH site blocks automatic readers, so their stories come through a news search. Confirm advisories with the source.', 'Walang feed ang PNA at hinaharang ng site ng DOH ang awtomatikong pagbasa, kaya ang balita nila ay dumadaan sa paghahanap ng balita. Kumpirmahin ang mga abiso sa pinagmulan.') + '</p>';
    }, src: 'Inquirer · Google News (PNA, DOH)'
  };

  // ---- the person's own feeds and watch words
  var feedsForm = function (d, withKeys) {
    var urls = d.feeds.filter(function (f) { return f.url; }).map(function (f) { return f.url; });
    return '<form class="wx-compose" data-s="rss:save">' + (withKeys !== 'only' ? field(T('My feeds, one https address per line (up to 12)', 'Mga feed ko, isang https address bawat linya (hanggang 12)'), '<textarea name="feeds" rows="3" placeholder="https://example.org/feed.xml">' + esc(urls.join('\n')) + '</textarea>') : '<input type="hidden" name="feeds" value="' + esc(urls.join('\n')) + '">') + (withKeys ? field(T('Words to watch, separated by commas', 'Mga salitang babantayan, pinaghihiwalay ng kuwit'), '<input name="keywords" maxlength="600" value="' + esc(d.keywords.join(', ')) + '" placeholder="Pasay, baha, brownout">') : '<input type="hidden" name="keywords" value="' + esc(d.keywords.join(', ')) + '">') + '<div class="wx-row"><button class="wx-btn is-pri">' + T('Save', 'I-save') + '</button><span class="wx-note">' + T('Only https addresses on the public internet are followed.', 'Ang mga https address lamang sa pampublikong internet ang sinusundan.') + '</span></div></form>';
  };
  var rssApi = {
    s: function (a, f) {
      WS.post({ action: 'feeds', feeds: f.feeds.value, keywords: f.keywords.value }).then(function (r) {
        if (r.error) { WS.toast(r.error, true); return; }
        var bad = (r.feeds || []).filter(function (x) { return !x.ok; });
        WS.toast(bad.length ? T(bad.length + ' feed' + (bad.length > 1 ? 's' : '') + ' could not be read or are not allowed: ' + host(bad[0].url), bad.length + ' feed ang hindi mabasa o hindi pinapayagan: ' + host(bad[0].url)) : T('Saved.', 'Na-save.'), !!bad.length);
        WS.refresh();
      });
    }
  };
  W.rss = Object.assign({
    r: function () {
      var d = ok(WS.group('rssmine')), own = d.feeds.filter(function (f) { return f.url; });
      return (own.length ? own.map(function (f) { return '<div class="wx-card2"><div class="wx-row"><b>' + esc(f.name) + '</b>' + A.pill(f.ok ? (f.stale ? T('older reading', 'lumang basa') : T('reading', 'nababasa')) : T("can't be read", 'hindi mabasa'), f.ok ? (f.stale ? '#F5A524' : L.ok) : L.urgent) + '<span class="wx-note" style="margin-left:auto">' + esc(host(f.url)) + '</span></div>' + (f.ok ? stories(f.items.slice(0, 3), { nosum: 1 }) : '<p class="wx-note">' + T('This feed did not answer. It will be tried again.', 'Hindi sumagot ang feed na ito. Susubukan itong muli.') + '</p>') + '</div>'; }).join('') : A.empty('rss', T('Follow any RSS feed', 'Sundan ang anumang RSS feed'), T('Paste a feed address below and it shows up here.', 'Mag-paste ng address ng feed sa ibaba at lalabas ito rito.'))) + feedsForm(d, false);
    }
  }, rssApi);
  W.rssmix = {
    r: function () {
      var d = ok(WS.group('rssmine'));
      if (!d.stream.length) return A.empty('rss', T('Your stream is empty', 'Walang laman ang iyong stream'), T('Follow a feed in My own feed, or add the news widgets to your rail: their feeds join this stream.', 'Sumunod sa feed sa Sarili kong feed, o idagdag ang mga widget ng balita sa rail: sasali ang mga feed nila sa stream na ito.'));
      return '<div class="wx-row"><b style="font:800 15px Urbanist">' + T('All my feeds', 'Lahat ng feed ko') + '</b><span class="wx-note" style="margin-left:auto">' + d.feeds.length + ' ' + T('feeds', 'feed') + ' · ' + d.stream.length + ' ' + T('stories', 'balita') + '</span></div>' + stories(d.stream.slice(0, 8), { words: d.keywords });
    }
  };
  W.rsskey = Object.assign({
    r: function () {
      var d = ok(WS.group('rssmine'));
      return (d.keywords.length ? '<div class="wx-row"><div class="wx-big" style="--c:' + (d.matches.length ? '#FFB000' : L.ok) + '"><b data-n="' + d.matches.length + '">' + d.matches.length + '</b><span>' + T('stories mention your words', 'balitang bumabanggit sa mga salita mo') + '</span></div>' + A.chips(d.keywords.map(function (w) { return A.pill(esc(w), '#FFB000'); })) + '</div>' + (d.matches.length ? stories(d.matches.slice(0, 5), { words: d.keywords }) : A.empty('check', T('Nothing matches right now', 'Walang tugma sa ngayon'), T('Watching ' + d.feeds.length + ' feeds.', 'Binabantayan ang ' + d.feeds.length + ' feed.'))) : A.empty('search', T('Choose words to watch', 'Pumili ng mga salitang babantayan'), T('For example: Pasay, baha, brownout, bagyo.', 'Halimbawa: Pasay, baha, brownout, bagyo.'))) + feedsForm(d, 'only').replace('<input type="hidden" name="keywords" value="' + esc(d.keywords.join(', ')) + '">', field(T('Words to watch, separated by commas', 'Mga salitang babantayan, pinaghihiwalay ng kuwit'), '<input name="keywords" maxlength="600" value="' + esc(d.keywords.join(', ')) + '" placeholder="Pasay, baha, brownout">'));
    }
  }, rssApi);
})();
