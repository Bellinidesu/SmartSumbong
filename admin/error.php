<?php
// Friendly error page (industry pass 3, 7 Oct 2026). Apache sends 403, 404
// and 500 here (ErrorDocument in the root .htaccess). Standalone on
// purpose: no session, no database, nothing that could fail in turn.
$code = (int) ($_SERVER['REDIRECT_STATUS'] ?? ($_GET['code'] ?? 404));
if (!in_array($code, [403, 404, 500], true)) { $code = 404; }
http_response_code($code);
$copy = [
    403 => ['That page is not open to the public', 'This address is not part of the portal.'],
    404 => ['We could not find that page', 'The link may be old, or the address may have a typo.'],
    500 => ['Something went wrong on our side', 'Please try again in a moment. If it keeps happening, tell the barangay office.'],
][$code];
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title><?= $code ?> — Smart Sumbong</title>
<link rel="icon" type="image/png" href="/admin/assets/img/favicon-64.png">
<link href="/admin/assets/css/fonts.css" rel="stylesheet">
<style>
  :root { --ink: #141B34; --muted: #6E7489; --bg: #F4F6FB; --card: #fff; --line: #E3E6EE; --blue: #00308F; --orange: #FF9800; }
  @media (prefers-color-scheme: dark) { :root { --ink: #E9ECF5; --muted: #9096AB; --bg: #0E1322; --card: #161C2E; --line: #273050; } }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px 16px; background: var(--bg); color: var(--ink); font: 15px/1.5 Urbanist, system-ui, sans-serif; }
  main { width: 100%; max-width: 440px; background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 36px 32px; text-align: center; display: grid; gap: 14px; justify-items: center; }
  img { width: 72px; height: 72px; }
  .code { font: 800 13px Inter, system-ui, sans-serif; letter-spacing: .1em; color: var(--orange); }
  h1 { margin: 0; font-size: 22px; font-weight: 800; text-wrap: balance; }
  p { margin: 0; color: var(--muted); }
  a { margin-top: 8px; display: inline-flex; align-items: center; height: 42px; padding: 0 22px; border-radius: 11px; background: var(--blue); color: #fff; font-weight: 700; text-decoration: none; }
  a:focus-visible { outline: 3px solid var(--orange); outline-offset: 2px; }
</style>
</head>
<body>
<main>
  <img src="/admin/assets/img/brgy-183-seal.webp" width="72" height="72" alt="Barangay 183 seal">
  <span class="code">ERROR <?= $code ?></span>
  <h1><?= htmlspecialchars($copy[0]) ?></h1>
  <p><?= htmlspecialchars($copy[1]) ?></p>
  <a href="/admin/login.php">Go to the portal</a>
</main>
</body>
</html>
