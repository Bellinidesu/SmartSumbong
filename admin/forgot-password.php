<?php
declare(strict_types=1);
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

// Admin-only. Residents and tanods sign in with a synthetic address
// derived from their phone number (migration 0021) that receives no
// mail, so this route would be a dead end for them — their recovery is
// the in-person counter reset in accounts.php. An admin signs in with a
// real email (login.php), so GoTrue's own recovery mail works here
// without needing Semaphore or anything else the barangay has not
// funded yet.

if (current_admin()) {
    header('Location: cases.php');
    exit;
}

$error = null;
$sent  = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $error = 'That form expired. Please try again.';
    } else {
        $email = trim((string) ($_POST['email'] ?? ''));
        if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $error = 'Enter the email address you sign in with.';
        } else {
            $redirectTo = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off' ? 'https://' : 'http://')
                        . $_SERVER['HTTP_HOST']
                        . dirname($_SERVER['SCRIPT_NAME']) . '/reset-password.php';
            try {
                Supabase::recover($email, $redirectTo);
            } catch (SupabaseError $ex) {
                // Logged, not shown — GoTrue answers the same way whether
                // or not the address has an account, and so must this
                // page. A caught error here is a delivery problem, not
                // proof one way or the other, so the visitor still sees
                // the same confirmation.
                error_log('SmartSumbong: password recovery request failed: ' . $ex->getMessage());
            }
            // Deliberately shown regardless of whether the call above
            // threw. Telling the two cases apart would tell a visitor
            // whether a given email address has an admin account.
            $sent = true;
        }
    }
}
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Forgot password — Smart Sumbong</title>
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
      <h1 class="login-title">Forgot password</h1>

      <?php if ($sent): ?>
        <p class="login-note">
          If that address belongs to an administrator account, a reset link
          has been sent. It expires after a while, so use it soon after it
          arrives.
        </p>
        <p class="login-signup">
          <a href="login.php">Back to sign in</a>
        </p>
      <?php else: ?>
        <?php if ($error): ?><p class="login-error" role="alert"><?= e($error) ?></p><?php endif; ?>

        <p class="field-hint" style="margin-bottom:16px;">
          Enter the email address you use to sign in. We'll send a link to
          reset your password.
        </p>

        <form method="post" novalidate>
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

          <label class="field">
            <span class="visually-hidden">Email address</span>
            <svg class="field-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
                 stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>
            </svg>
            <input type="email" name="email" placeholder="Email address" autocomplete="username"
                   value="<?= e($_POST['email'] ?? '') ?>" required autofocus>
          </label>

          <button class="login-btn" type="submit">Send reset link</button>
        </form>

        <p class="login-signup">
          <a href="login.php">Back to sign in</a>
        </p>
      <?php endif; ?>
    </div>
</section>
</div>
</body>
</html>
