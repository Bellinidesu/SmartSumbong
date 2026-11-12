/* An emoji picker (12 Nov 2026): categories, a search, a row of the ones used lately. It draws the emoji of the device it runs on, so
   there is no font or image to download. window.ssEmoji.open(anchorButton, function (emoji) { ... }) opens it beside the button. */
(function () {
  'use strict';
  var tr = function (en, fil) { return typeof window.T === 'function' ? window.T(en, fil) : en; };
  var CATS = [
    { id: 'smile', ic: '😀', en: 'Smileys', fil: 'Mukha', kw: 'face smile happy sad laugh cry angry love kiss wink cool tired sick mask',
      e: '😀 😃 😄 😁 😆 😅 😂 🤣 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 😚 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 😐 😑 😶 😏 😒 🙄 😬 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🥵 🥶 🥴 😵 🤯 🤠 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬' },
    { id: 'hands', ic: '👍', en: 'Hands', fil: 'Kamay', kw: 'thumbs up down ok clap pray hand wave point peace strong muscle handshake',
      e: '👍 👎 👌 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 🤝 🙏 ✍️ 💪 👏 🙌 👐 🤲 🫡' },
    { id: 'hearts', ic: '❤️', en: 'Hearts and symbols', fil: 'Puso at simbolo', kw: 'heart love star fire hundred check cross warning question arrow',
      e: '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ✨ ⭐ 🌟 💫 🔥 💯 ✅ ❌ ⚠️ ❗ ❓ ➕ ➖ ✔️ ➡️ ⬅️ ⬆️ ⬇️ 🔴 🟠 🟡 🟢 🔵' },
    { id: 'help', ic: '🚨', en: 'Help and places', fil: 'Tulong at lugar', kw: 'police ambulance fire truck siren hospital house school phone map pin light lock key note calendar clock tool',
      e: '🚨 🚓 🚒 🚑 🚧 📞 📱 💻 📷 🎥 📍 🗺️ 🏠 🏢 🏫 🏥 🏛️ 🔦 🔒 🔑 📌 📎 📝 📅 ⏰ ⌛ 💡 🔧 🔨 🧯 🪜 🚰 🗑️ 🚮' },
    { id: 'nature', ic: '🌧️', en: 'Weather and animals', fil: 'Panahon at hayop', kw: 'sun rain storm typhoon flood wind water rainbow tree dog cat rat snake',
      e: '☀️ 🌤️ ⛅ 🌧️ ⛈️ 🌩️ 🌪️ 🌀 🌊 💧 ☔ 🌈 ❄️ 🌳 🌴 🌱 🐶 🐱 🐕 🐈 🐀 🐍 🐔 🐖 🦟' },
    { id: 'food', ic: '🍚', en: 'Food and drink', fil: 'Pagkain', kw: 'rice noodle bread burger pizza chicken egg fruit coffee tea drink',
      e: '🍚 🍜 🍞 🍔 🍟 🍕 🌭 🍗 🥚 🍎 🍌 🍉 🥭 ☕ 🍵 🥤 🍺 💧' },
    { id: 'fun', ic: '🎉', en: 'Celebrate', fil: 'Selebrasyon', kw: 'party balloon cake gift trophy flag philippines ball',
      e: '🎉 🎊 🎈 🎂 🎁 🏆 🥇 🇵🇭 ⚽ 🏀 🎵 🎶' }
  ];
  var WORDS = { thumbs: '👍', thumb: '👍', like: '👍', ok: '👌', heart: '❤️', love: '❤️', fire: '🔥', pray: '🙏', thanks: '🙏', salamat: '🙏', clap: '👏', cry: '😭', sad: '😢', laugh: '😂', haha: '😂', smile: '😊',
    angry: '😡', wow: '😮', think: '🤔', sorry: '🙏', help: '🆘', tulong: '🚨', siren: '🚨', police: '🚓', pulis: '🚓', ambulance: '🚑', fire_truck: '🚒', bumbero: '🚒', flood: '🌊', baha: '🌊', rain: '🌧️',
    ulan: '🌧️', typhoon: '🌀', bagyo: '🌀', check: '✅', done: '✅', warning: '⚠️', question: '❓', phone: '📞', house: '🏠', bahay: '🏠', hospital: '🏥', school: '🏫', map: '🗺️', pin: '📍', light: '💡', ilaw: '💡',
    water: '💧', tubig: '💧', rat: '🐀', daga: '🐀', dog: '🐶', aso: '🐶', cat: '🐱', pusa: '🐱', snake: '🐍', ahas: '🐍', coffee: '☕', rice: '🍚', kanin: '🍚', party: '🎉', flag: '🇵🇭' };
  var RK = 'ss-emoji-recent';
  function rd() { try { var v = JSON.parse(localStorage.getItem(RK)); return Array.isArray(v) ? v : []; } catch (e) { return []; } }
  function remember(e) { var r = rd().filter(function (x) { return x !== e; }); r.unshift(e); try { localStorage.setItem(RK, JSON.stringify(r.slice(0, 24))); } catch (x) { /* private window */ } }
  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) { n.className = cls; } if (text != null) { n.textContent = text; } return n; }

  var pop = null, back = null, onPick = null;
  function close(refocus) {
    if (!pop) { return; }
    pop.remove(); pop = null; document.removeEventListener('pointerdown', outside, true); document.removeEventListener('keydown', key, true); window.removeEventListener('resize', closeNow);
    if (refocus && back) { back.focus(); }
  }
  function closeNow() { close(false); }
  function outside(e) { if (pop && !pop.contains(e.target) && !(back && back.contains(e.target))) { close(false); } }
  function key(e) { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(true); } }
  function cell(e) { var b = el('button', 'em-c', e); b.type = 'button'; b.setAttribute('aria-label', e); b.setAttribute('data-e', e); return b; }

  function fill(grid, q) {
    grid.textContent = '';
    q = (q || '').trim().toLowerCase();
    var any = false;
    function section(title, list) { if (!list.length) { return; } any = true; grid.appendChild(el('p', 'em-h', title)); var g = el('div', 'em-g'); list.forEach(function (e) { g.appendChild(cell(e)); }); grid.appendChild(g); }
    if (q === '') {
      section(tr('Used lately', 'Ginamit kamakailan'), rd());
      CATS.forEach(function (c) { section(tr(c.en, c.fil), c.e.split(' ')); });
    } else {
      var hit = [];
      Object.keys(WORDS).forEach(function (w) { if (w.indexOf(q) === 0 || w.replace('_', ' ').indexOf(q) >= 0) { hit.push(WORDS[w]); } });
      section(tr('Matches', 'Mga tugma'), hit.filter(function (e, i) { return hit.indexOf(e) === i; }));
      CATS.forEach(function (c) { if ((c.en + ' ' + c.fil + ' ' + c.kw).toLowerCase().indexOf(q) >= 0) { section(tr(c.en, c.fil), c.e.split(' ')); } });
    }
    if (!any) { grid.appendChild(el('p', 'em-none', tr('No emoji match that.', 'Walang emoji na tugma.'))); }
  }

  function open(anchor, cb) {
    close(false); back = anchor; onPick = cb;
    pop = el('div', 'em-pop'); pop.setAttribute('role', 'dialog'); pop.setAttribute('aria-label', tr('Emoji', 'Emoji'));
    var s = el('input', 'em-q'); s.type = 'search'; s.placeholder = tr('Search emoji', 'Hanapin ang emoji'); s.setAttribute('aria-label', tr('Search emoji', 'Hanapin ang emoji'));
    var tabs = el('div', 'em-tabs'); tabs.setAttribute('role', 'group'); tabs.setAttribute('aria-label', tr('Categories', 'Mga kategorya'));
    var grid = el('div', 'em-grid'); grid.tabIndex = 0;
    CATS.forEach(function (c) {
      var t = el('button', 'em-t', c.ic); t.type = 'button'; t.setAttribute('aria-label', tr(c.en, c.fil)); t.title = tr(c.en, c.fil);
      t.addEventListener('click', function () { s.value = ''; fill(grid, ''); var h = [].slice.call(grid.querySelectorAll('.em-h')).filter(function (x) { return x.textContent === tr(c.en, c.fil); })[0]; if (h) { grid.scrollTop = h.offsetTop - grid.offsetTop; } });
      tabs.appendChild(t);
    });
    pop.appendChild(s); pop.appendChild(tabs); pop.appendChild(grid);
    pop.addEventListener('click', function (e) { var b = e.target.closest('.em-c'); if (!b) { return; } var em = b.getAttribute('data-e'); remember(em); if (onPick) { onPick(em); } });
    s.addEventListener('input', function () { fill(grid, s.value); });
    fill(grid, '');
    document.body.appendChild(pop);
    var r = anchor.getBoundingClientRect(), w = pop.offsetWidth, h = pop.offsetHeight;
    pop.style.left = Math.max(8, Math.min(r.right - w, window.innerWidth - w - 8)) + 'px';
    pop.style.top = Math.max(8, r.top - h - 8 < 8 ? r.bottom + 8 : r.top - h - 8) + 'px';
    document.addEventListener('pointerdown', outside, true); document.addEventListener('keydown', key, true); window.addEventListener('resize', closeNow);
    s.focus();
  }
  window.ssEmoji = { open: open, close: function () { close(false); } };
})();
