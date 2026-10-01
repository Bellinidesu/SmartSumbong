<?php
declare(strict_types=1);
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

if (current_admin()) {
    header('Location: cases.php');
    exit;
}

$error  = null;
$notice = match (true) {
    isset($_GET['expired']) => t('Your session ended. Please sign in again.',
                                 'Natapos na ang iyong session. Mag-sign in muli.'),
    isset($_GET['reset'])   => t('Your password has been changed. Sign in with your new password.',
                                 'Napalitan na ang iyong password. Mag-sign in gamit ang bagong password.'),
    default                 => null,
};

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $error = t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.');
    } else {
        try {
            attempt_login(trim($_POST['email'] ?? ''), $_POST['password'] ?? '');
            header('Location: cases.php');
            exit;
        } catch (SupabaseError $ex) {
            // GoTrue phrases a wrong password as invalid credentials; say
            // it the way the person at the desk would understand it.
            $error = str_contains(strtolower($ex->getMessage()), 'invalid login')
                ? t('That email and password do not match an account.',
                    'Walang account na tugma sa email at password na iyan.')
                : safe_error($ex);
        }
    }
}
?><!DOCTYPE html>
<html lang="<?= html_lang() ?>">
<head>
<meta charset="utf-8">
<?= theme_head() ?>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e(t('Sign in', 'Mag-sign in')) ?> — Smart Sumbong</title>
<link href="assets/css/fonts.css?v=<?= e(asset_version('fonts.css')) ?>" rel="stylesheet">
<link href="assets/css/app.css?v=<?= e(asset_version('app.css')) ?>" rel="stylesheet">
</head>
<body class="login-body">

<div class="login-split">

  <!-- Left rail: barangay identity. Assets are dropped in by the team;
       each falls back to text so the page never shows a broken image. -->
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

  <!-- Right panel: orange field with the barangay photo washed behind it.
       Accepts either extension — whichever the team exported. -->
  <section class="login-panel">
    <?= prefs_switches('prefs--login') ?>
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
      <h1 class="login-title"><?= e(t('Account Login', 'Pag-login sa Account')) ?></h1>

      <?php if ($notice): ?><p class="login-note"><?= e($notice) ?></p><?php endif; ?>
      <?php if ($error): ?><p class="login-error" role="alert"><?= e($error) ?></p><?php endif; ?>

      <form method="post" novalidate>
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <label class="field">
          <span class="visually-hidden"><?= e(t('Email address', 'Email address')) ?></span>
          <svg class="field-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
               stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>
          </svg>
          <input type="email" name="email" placeholder="<?= e(t('Email address', 'Email address')) ?>" autocomplete="username"
                 value="<?= e($_POST['email'] ?? '') ?>" required autofocus>
        </label>

        <label class="field">
          <span class="visually-hidden"><?= e(t('Password', 'Password')) ?></span>
          <svg class="field-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
               stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>
          </svg>
          <input type="password" name="password" placeholder="<?= e(t('Password', 'Password')) ?>"
                 autocomplete="current-password" required>
        </label>

        <div class="login-meta">
          <label class="remember"><input type="checkbox" name="remember" value="1"> <?= e(t('Remember me', 'Tandaan ako')) ?></label>
          <a class="forgot" href="forgot-password.php"><?= e(t('Forgot password?', 'Nakalimutan ang password?')) ?></a>
        </div>

        <p class="caps-warn" id="caps" hidden role="status"><?= e(t('Caps Lock is on.', 'Naka-on ang Caps Lock.')) ?></p>

        <button class="login-btn" type="submit"><?= e(t('Login', 'Mag-login')) ?></button>
      </form>

      <p class="login-signup">
        <?= e(t('No account?', 'Walang account?')) ?> <a href="request-access.php"><?= e(t('Request access here', 'Humiling ng access dito')) ?></a>
      </p>
    </div>
</section>
</div>

<script>
// Two failed sign-ins in a row are usually this, and nobody thinks to check.
(function () {
  var warn = document.getElementById('caps');
  var pw   = document.querySelector('input[type="password"]');
  if (!warn || !pw) return;
  function check(ev) {
    if (typeof ev.getModifierState !== 'function') return;
    ev.getModifierState('CapsLock')
      ? warn.removeAttribute('hidden')
      : warn.setAttribute('hidden', '');
  }
  pw.addEventListener('keydown', check);
  pw.addEventListener('keyup', check);
  pw.addEventListener('blur', function () { warn.setAttribute('hidden', ''); });
})();
</script>
</body>
</html>
