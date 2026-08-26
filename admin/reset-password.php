<?php
declare(strict_types=1);
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/auth.php';

// Reached from the link forgot-password.php asked GoTrue to email.
//
// GoTrue delivers the recovery grant as a URL fragment — #access_token=
// ...&type=recovery — never as a query string, and a fragment is never
// sent to the server by the browser. So this page cannot read it in PHP
// at all; the moment of "is this link still good" and the password
// update itself both have to happen in JS, straight against Supabase's
// REST API with the same publishable key the rest of the portal already
// exposes to the browser (config.php). Nothing here needs a PHP admin
// session — the recovery token from the link *is* the credential, and
// it is short-lived and single-purpose by GoTrue's own design.
//
// On success this sends the visitor back to login.php to sign in with
// the new password normally, rather than trying to hand-roll a portal
// session from a recovery grant — that would have to duplicate every
// check attempt_login() already does (role, suspension) and get it
// exactly as right.
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Set a new password — Smart Sumbong</title>
<link href="assets/css/fonts.css" rel="stylesheet">
<link href="assets/css/app.css" rel="stylesheet">
</head>
<body class="login-body">

<div class="login-split">

  <aside class="login-rail">
    <?php foreach ([
        ['brgy-183-seal.png',   'Barangay 183 Zone 20, Villamor, Pasay City'],
        ['bagong-pilipinas.png','Bagong Pilipinas'],
        ['bagong-villamor.png', 'Barangay 183 Bagong Villamor'],
    ] as [$file, $alt]): ?>
      <?php if (is_file(__DIR__ . '/assets/img/' . $file)): ?>
        <img class="rail-logo" src="assets/img/<?= e($file) ?>" alt="<?= e($alt) ?>">
      <?php else: ?>
        <div class="rail-logo rail-logo--missing" role="img" aria-label="<?= e($alt) ?>"><?= e($alt) ?></div>
      <?php endif; ?>
    <?php endforeach; ?>
  </aside>

  <section class="login-panel">
    <?php
    $bg = null;
    foreach (['villamor-street.jpg', 'villamor-street.png'] as $candidate) {
        if (is_file(__DIR__ . '/assets/img/' . $candidate)) { $bg = $candidate; break; }
    }
    ?>
    <?php if ($bg): ?>
      <img class="login-panel-bg" src="assets/img/<?= e($bg) ?>" alt="" aria-hidden="true">
    <?php endif; ?>

    <?php if (is_file(__DIR__ . '/assets/img/logo-wordmark.png')): ?>
      <img class="login-wordmark" src="assets/img/logo-wordmark.png" alt="Smart Sumbong">
    <?php else: ?>
      <div class="login-wordmark login-wordmark--missing">Smart<br>Sumbong</div>
    <?php endif; ?>

    <div class="login-card">
      <h1 class="login-title">Set a new password</h1>

      <p id="reset-error" class="login-error" role="alert" hidden></p>

      <p id="reset-expired" class="login-note" hidden>
        This link is no longer valid — it may have already been used, or it
        expired before you opened it. Request a new one from the sign-in page.
      </p>

      <form id="reset-form" novalidate hidden>
        <label class="field">
          <span class="visually-hidden">New password</span>
          <svg class="field-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
               stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>
          </svg>
          <input type="password" id="new-password" placeholder="New password"
                 autocomplete="new-password" required>
        </label>
        <p class="field-hint">At least 8 characters.</p>

        <label class="field">
          <span class="visually-hidden">Confirm new password</span>
          <svg class="field-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
               stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>
          </svg>
          <input type="password" id="confirm-password" placeholder="Confirm new password"
                 autocomplete="new-password" required>
        </label>

        <button class="login-btn" type="submit" id="reset-submit">Save password</button>
      </form>

      <p class="login-signup">
        <a href="login.php">Back to sign in</a>
      </p>
    </div>
</section>
</div>

<script>
(function () {
  var SUPABASE_URL = <?= json_encode(supabase_url()) ?>;
  var SUPABASE_ANON_KEY = <?= json_encode(supabase_key()) ?>;

  var hash = window.location.hash.length > 1 ? window.location.hash.slice(1) : '';
  var params = new URLSearchParams(hash);
  var accessToken = params.get('access_token');
  var type = params.get('type');
  var hashError = params.get('error_description') || params.get('error');

  var formEl     = document.getElementById('reset-form');
  var errorEl    = document.getElementById('reset-error');
  var expiredEl  = document.getElementById('reset-expired');

  function showError(msg) {
    errorEl.textContent = msg;
    errorEl.hidden = false;
  }

  if (hashError || !accessToken || type !== 'recovery') {
    expiredEl.hidden = false;
    return;
  }

  formEl.hidden = false;

  formEl.addEventListener('submit', function (ev) {
    ev.preventDefault();
    errorEl.hidden = true;

    var pw = document.getElementById('new-password').value;
    var confirm = document.getElementById('confirm-password').value;

    if (pw.length < 8) {
      showError('Your password must be at least 8 characters long.');
      return;
    }
    if (pw !== confirm) {
      showError('The two passwords do not match.');
      return;
    }

    var btn = document.getElementById('reset-submit');
    btn.disabled = true;
    btn.textContent = 'Saving…';

    fetch(SUPABASE_URL + '/auth/v1/user', {
      method: 'PUT',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': 'Bearer ' + accessToken,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ password: pw }),
    }).then(function (res) {
      if (!res.ok) {
        return res.json().catch(function () { return {}; }).then(function (data) {
          throw new Error(data.msg || data.error_description || data.message || 'Could not set your new password.');
        });
      }
      window.location.replace('login.php?reset=1');
    }).catch(function (err) {
      btn.disabled = false;
      btn.textContent = 'Save password';
      showError('This link may have expired — ' + err.message
        + ' Request a new one from the sign-in page.');
    });
  });
})();
</script>
</body>
</html>
