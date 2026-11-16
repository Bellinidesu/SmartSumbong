/* The case page's chat button (16 Nov 2026, Ace): beside the SMART brain. One press does what the handler chose in the menu beside it:
   "Chat head" opens the case's chat head here and floats it on every page, "Case chat" opens the case's chat in the Inbox with no bubble.
   The choice is kept in this browser (like the rest of the chat head's choices). The unread count of the chat head shows on the button. */
(function () {
  'use strict';
  var root = document.getElementById('cc-chat'); if (!root) { return; }
  var KEY = 'ss-case-chat-mode', id = root.getAttribute('data-case');
  var go = root.querySelector('[data-cc-inbox]');   // a real link, drawn by the page; the button only follows it
  var btn = root.querySelector('[data-cc-chat]'), car = root.querySelector('[data-cc-chat-menu]'), menu = root.querySelector('.ss-chatmenu'), n = root.querySelector('.ss-chatn');
  var T = window.T || function (en) { return en; };
  var mode = 'head'; try { mode = localStorage.getItem(KEY) === 'page' ? 'page' : 'head'; } catch (e) { /* the default */ }

  function paint() {
    [].forEach.call(menu.querySelectorAll('[data-cc-mode]'), function (b) { b.setAttribute('aria-checked', String(b.getAttribute('data-cc-mode') === mode)); });
    var tip = mode === 'head' ? T('Case chat: opens the chat head', 'Chat ng kaso: bubuksan ang chat head') : T('Case chat: opens it in the Inbox', 'Chat ng kaso: bubuksan sa Inbox');
    btn.title = tip; btn.setAttribute('aria-label', tip);
    document.documentElement.classList.toggle('cc-chat-page', mode === 'page');   // a handler who does not want the bubble does not get it on this page
  }
  function closeMenu() { menu.hidden = true; car.setAttribute('aria-expanded', 'false'); }
  function openMenu() { menu.hidden = false; car.setAttribute('aria-expanded', 'true'); var on = menu.querySelector('[aria-checked="true"]'); if (on) { on.focus(); } }

  btn.addEventListener('click', function () {
    if (mode === 'page') { if (go) { go.click(); } return; }
    var core = window.ssChatCore;
    if (core && core.store) { core.store.patch(id, { pin: true }); }   // it floats on every other page too
    var head = document.getElementById('chat-head'), panel = document.getElementById('ch-panel'), fab = document.getElementById('ch-fab');
    if (panel && fab && panel.hidden) { fab.click(); } else if (head && panel && !panel.hidden) { fab.click(); }
  });
  car.addEventListener('click', function (e) { e.stopPropagation(); if (menu.hidden) { openMenu(); } else { closeMenu(); } });
  menu.addEventListener('click', function (e) {
    var b = e.target.closest('[data-cc-mode]'); if (!b) { return; }
    mode = b.getAttribute('data-cc-mode'); try { localStorage.setItem(KEY, mode); } catch (er) { /* kept until the page closes */ }
    paint(); closeMenu(); btn.focus();
  });
  document.addEventListener('click', function (e) { if (!menu.hidden && !root.contains(e.target)) { closeMenu(); } });
  root.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !menu.hidden) { e.stopPropagation(); closeMenu(); car.focus(); }
    if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && !menu.hidden) { e.preventDefault(); var bs = [].slice.call(menu.querySelectorAll('[data-cc-mode]')), i = bs.indexOf(document.activeElement); bs[(i + (e.key === 'ArrowDown' ? 1 : bs.length - 1)) % bs.length].focus(); }
  });

  // the unread count of the chat head, on the button
  var badge = document.getElementById('ch-badge');
  function sync() { if (!badge) { return; } var c = badge.hidden ? '' : badge.textContent.trim(); n.textContent = c; n.hidden = c === ''; }
  if (badge) { new MutationObserver(sync).observe(badge, { attributes: true, childList: true, characterData: true, subtree: true }); sync(); }
  paint();
})();
