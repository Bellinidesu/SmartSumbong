<?php
/**
 * Linked from the sign-in page, which previously pointed at a file that
 * did not exist — a 404 in front of the client.
 *
 * There is deliberately no self-service portal signup. Administrator
 * accounts are created by appointment through Transfer Administration,
 * and residents register in the mobile app where their ID can be
 * captured and verified.
 */
declare(strict_types=1);
// config.php carries e(); layout.php alone left the page a 500 the
// moment it printed its first stylesheet link.
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/layout.php';
?><!DOCTYPE html>
<html lang="<?= html_lang() ?>">
<head>
<meta charset="utf-8">
<?= theme_head() ?>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Request access — Smart Sumbong | Barangay 183</title>
<link rel="icon" type="image/png" href="assets/img/brgy-183-seal.png">
<link href="assets/css/fonts.css?v=<?= e(asset_version('fonts.css')) ?>" rel="stylesheet">
<link href="assets/css/app.css?v=<?= e(asset_version('app.css')) ?>" rel="stylesheet">
</head>
<body class="login-body">

<!-- The sign-in page's own layout (branch B), so following its "Request
     access here" link lands on the same screen rather than a bare card. -->
<div class="login-split">
  <aside class="login-rail">
    <?php foreach ([
        ['brgy-183-seal.png',   'Barangay 183 Zone 20, Villamor, Pasay City'],
        ['bagong-pilipinas.png','Bagong Pilipinas'],
        ['bagong-villamor.png', 'Barangay 183 Bagong Villamor'],
    ] as [$file, $alt]): ?>
      <?php if (is_file(__DIR__ . '/assets/img/' . $file)): ?>
        <img class="rail-logo" src="assets/img/<?= e($file) ?>" alt="<?= e($alt) ?>">
      <?php endif; ?>
    <?php endforeach; ?>
  </aside>

  <section class="login-panel">
    <?= prefs_switches('prefs--login') ?>
    <?php if (is_file(__DIR__ . '/assets/img/villamor-street.jpg')): ?>
      <img class="login-panel-bg" src="assets/img/villamor-street.jpg" alt="" aria-hidden="true">
    <?php endif; ?>
    <?php if (is_file(__DIR__ . '/assets/img/logo-wordmark.png')): ?>
      <img class="login-wordmark" src="assets/img/logo-wordmark.png" alt="Smart Sumbong">
    <?php endif; ?>

    <div class="login-card access-card">
      <h1 class="login-title">Requesting access</h1>
      <p class="access-lead">
        This portal is for barangay administrators. Accounts are not created here.
      </p>

      <h2 class="access-sub">If you are a resident</h2>
      <p class="access-text">
        File complaints through the Smart Sumbong mobile app. Register there with a
        valid government-issued ID and the barangay will verify your account.
      </p>

      <h2 class="access-sub">If you are barangay staff</h2>
      <p class="access-text">
        Administrator access is granted by the current administrator through the
        portal. Speak to them, or to the barangay IT administrator.
      </p>

      <a class="login-btn access-back" href="login.php">Back to sign in</a>
    </div>
  </section>
</div>
</body>
</html>
