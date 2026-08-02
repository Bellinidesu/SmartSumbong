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
require_once __DIR__ . '/includes/layout.php';
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Request access — Smart Sumbong | Barangay 183</title>
<link rel="icon" type="image/png" href="assets/img/brgy-183-seal.png">
<link href="assets/css/fonts.css" rel="stylesheet">
<link href="assets/css/app.css" rel="stylesheet">
</head>
<body class="doc-body">
<section class="card confirm-card">
  <h1 class="case-heading">Requesting access</h1>

  <p class="case-body">
    This portal is for barangay administrators. Accounts are not created here.
  </p>

  <div class="case-block">
    <h3 class="case-sub">If you are a resident</h3>
    <p class="case-body">
      File complaints through the Smart Sumbong mobile app. Register there with a
      valid government-issued ID and the barangay will verify your account.
    </p>
  </div>

  <div class="case-block">
    <h3 class="case-sub">If you are barangay staff</h3>
    <p class="case-body">
      Administrator access is granted by the current administrator through the
      portal. Speak to them, or to the barangay IT administrator.
    </p>
  </div>

  <div class="confirm-actions">
    <a class="btn-accept" href="login.php">Back to sign in</a>
  </div>
</section>
</body>
</html>
