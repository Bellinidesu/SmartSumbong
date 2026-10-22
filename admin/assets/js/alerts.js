// Alerts on the profile (0136): this browser's alerts on or off, and every choice saved the moment it changes.
(function () {
  var box = document.getElementById('ss-al');
  if (!box) return;
  var T = window.T || function (en) { return en; };
  var csrf = box.dataset.csrf, vapid = box.dataset.vapid;
  var $ = function (id) { return document.getElementById(id); };
  var state = $('ss-al-state'), on = $('ss-al-on'), off = $('ss-al-off'), test = $('ss-al-test'), saved = $('ss-al-saved');

  function post(data) {
    var f = new FormData();
    f.append('csrf', csrf);
    Object.keys(data).forEach(function (k) { f.append(k, data[k]); });
    return fetch('alerts-act.php', { method: 'POST', body: f, credentials: 'same-origin' }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (!r.ok || j.error) throw new Error(j.error || T('Could not save. Try again.', 'Hindi ma-save. Subukan muli.'));
        return j;
      });
    });
  }
  function say(msg, bad) { saved.textContent = msg + ' '; saved.classList.toggle('bad', !!bad); }
  function done() { say(T('Saved.', 'Na-save.')); }
  function fail(e) { say(e && e.message ? e.message : String(e), true); }

  // "Chrome on Windows", for the list of their browsers
  function label() {
    var u = navigator.userAgent;
    var b = /Edg\//.test(u) ? 'Edge' : /OPR\//.test(u) ? 'Opera' : /Firefox\//.test(u) ? 'Firefox' : /Chrome\//.test(u) ? 'Chrome' : /Safari\//.test(u) ? 'Safari' : T('A browser', 'Isang browser');
    var os = /Windows/.test(u) ? 'Windows' : /Android/.test(u) ? 'Android' : /iPhone|iPad/.test(u) ? 'iPhone' : /Mac OS/.test(u) ? 'Mac' : /Linux/.test(u) ? 'Linux' : '';
    return b + (os ? T(' on ', ' sa ') + os : '');
  }
  function bytes(b64) {
    var s = atob((b64 + '==='.slice((b64.length + 3) % 4)).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(s, function (c) { return c.charCodeAt(0); });
  }

  var reg = null;
  function show(sub) {
    var blocked = window.Notification && Notification.permission === 'denied';
    on.hidden = !!sub || blocked; off.hidden = !sub;
    state.textContent = sub ? T('On. Alerts reach this browser even with the portal closed.', 'Bukas. Dumarating ang alerto kahit sarado ang portal.')
      : blocked ? T('This browser blocks the portal\'s alerts. Allow them in the site settings (the icon by the address), then reload.', 'Hinaharang ng browser ang alerto ng portal. Payagan ito sa site settings (ang icon sa tabi ng address), saka i-reload.')
      : T('Off.', 'Sarado.');
  }
  function save(sub) {
    var j = sub.toJSON();
    return post({ action: 'subscribe', endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth, label: label() });
  }

  if (vapid && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window) {
    navigator.serviceWorker.register('sw.js', { scope: './' })
      .then(function (r) { reg = r; return r.pushManager.getSubscription(); })
      // saved again on each visit: keeps the row, and moves it to whoever signed in on a shared computer
      .then(function (sub) { show(sub); if (sub) save(sub).catch(function () {}); })
      .catch(function () { state.textContent = T('Alerts could not start in this browser.', 'Hindi mabuksan ang alerto sa browser na ito.'); });
    on.addEventListener('click', function () {
      on.disabled = true;
      Notification.requestPermission().then(function (p) {
        if (p !== 'granted') throw new Error(T('Alerts were not allowed in this browser.', 'Hindi pinayagan ang alerto sa browser na ito.'));
        return reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: bytes(vapid) });
      }).then(function (sub) { return save(sub).then(function () { show(sub); done(); }); })
        .catch(fail).then(function () { on.disabled = false; });
    });
    off.addEventListener('click', function () {
      reg.pushManager.getSubscription().then(function (sub) {
        if (!sub) return show(null);
        var ep = sub.endpoint;
        return sub.unsubscribe().then(function () { return post({ action: 'unsubscribe', endpoint: ep }); }).then(function () { show(null); done(); });
      }).catch(fail);
    });
  } else if (vapid) {
    state.textContent = T('This browser cannot show alerts. On an iPhone, add the portal to the Home Screen first.', 'Hindi kaya ng browser na ito ang alerto. Sa iPhone, idagdag muna ang portal sa Home Screen.');
  }

  test.addEventListener('click', function () {
    test.disabled = true;
    post({ action: 'test' })
      .then(function () { say(T('Test sent to your browsers and phone with alerts on. It should arrive in a few seconds.', 'Naipadala ang test sa mga browser at telepono mong may alerto. Darating ito sa loob ng ilang segundo.')); })
      .catch(fail).then(function () { setTimeout(function () { test.disabled = false; }, 3000); });
  });

  box.querySelectorAll('[data-kind]').forEach(function (cb) {
    cb.addEventListener('change', function () {
      post({ action: 'mute', kind: cb.dataset.kind, muted: cb.checked ? '0' : '1' }).then(done).catch(function (e) { cb.checked = !cb.checked; fail(e); });
    });
  });

  var scope = $('ss-al-scope'), from = $('ss-al-from'), to = $('ss-al-to'), urgent = $('ss-al-urgent');
  function quietUi() { $('ss-al-tow').hidden = urgent.disabled = from.value === ''; }
  function choices() {
    return post({ action: 'choices', scope: scope.querySelector('[aria-checked="true"]').dataset.scope,
      quiet_from: from.value, quiet_to: from.value === '' ? '' : to.value, quiet_urgent: urgent.checked ? '1' : '0' }).then(done).catch(fail);
  }
  scope.querySelectorAll('button').forEach(function (b) {
    b.addEventListener('click', function () {
      scope.querySelectorAll('button').forEach(function (x) { x.classList.toggle('p-on', x === b); x.setAttribute('aria-checked', x === b ? 'true' : 'false'); });
      choices();
    });
  });
  from.addEventListener('change', function () { quietUi(); choices(); });
  to.addEventListener('change', choices);
  urgent.addEventListener('change', choices);
  quietUi();

  var list = $('ss-al-list');
  if (list) list.addEventListener('click', function (e) {
    var b = e.target.closest('[data-remove]');
    if (!b) return;
    var li = b.closest('li'), ep = li.dataset.endpoint;
    post({ action: 'unsubscribe', endpoint: ep }).then(function () {
      li.remove(); done();
      if (reg) reg.pushManager.getSubscription().then(function (s) { if (s && s.endpoint === ep) s.unsubscribe().then(function () { show(null); }); });
    }).catch(fail);
  });
})();
