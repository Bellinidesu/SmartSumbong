// Cloudflare Turnstile for Supabase Auth's CAPTCHA protection (backend
// review, 10 Oct 2026). Only loaded when TURNSTILE_SITE_KEY is set
// (turnstile_tags() in includes/config.php).
//
// Every form that sends a password to Supabase (sign in, the "your
// password" confirmations) or asks it for a reset link (data-captcha) gets
// a fresh token on submit: the submit waits, the hidden widget solves the
// challenge (showing itself only if a person has to click), and the form
// goes on with cf-turnstile-response, which Supabase::signIn() and
// Supabase::recover() pass along.
(function () {
  var box = document.getElementById('ss-turnstile');
  if (!box) return;
  var id = null;
  var waiting = null;

  function needsToken(form) {
    return form.hasAttribute('data-captcha') || form.querySelector('input[type=password]');
  }
  function answer(token) {
    var go = waiting;
    waiting = null;
    if (go) go(token);
  }

  document.addEventListener('submit', function (e) {
    var form = e.target;
    if (e.defaultPrevented || !needsToken(form)) return;
    if (form.dataset.tsOk) { delete form.dataset.tsOk; return; }
    if (!window.turnstile) return; // blocked or still loading: Supabase decides
    e.preventDefault();
    var submitter = e.submitter || null;
    waiting = function (token) {
      var input = form.querySelector('input[name="cf-turnstile-response"]');
      if (!input) {
        input = document.createElement('input');
        input.type = 'hidden';
        input.name = 'cf-turnstile-response';
        form.appendChild(input);
      }
      input.value = token;
      form.dataset.tsOk = '1';
      if (form.requestSubmit) form.requestSubmit(submitter); else form.submit();
    };
    if (id === null) {
      id = window.turnstile.render(box, {
        sitekey: box.getAttribute('data-sitekey'),
        execution: 'execute',
        appearance: 'interaction-only',
        callback: answer,
        // A challenge that cannot finish still sends the form; Supabase
        // then refuses it and the page says why.
        'error-callback': function () { answer(''); }
      });
    } else {
      window.turnstile.reset(id);
    }
    window.turnstile.execute(id);
  });
})();
