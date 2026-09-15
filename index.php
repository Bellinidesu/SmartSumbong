<?php
declare(strict_types=1);
/**
 * Bare-domain landing page.
 *
 * admin/ and public/ each stood alone with no front door — hitting the
 * domain root fell straight into the .htaccess deny-everything-else rule.
 * Now that this is deployed somewhere real for the defense (not just
 * `php -S` on a laptop), the root should say what SmartSumbong is and
 * point at the two things a visitor can actually reach.
 */
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SmartSumbong — Barangay 183, Pasay City</title>
<link rel="icon" type="image/png" href="admin/assets/img/brgy-183-seal.png">
<link href="admin/assets/css/fonts.css" rel="stylesheet">
<style>
  :root { --navy:#00308F; --navy-dark:#001c57; --orange:#FF9800; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh;
    display: flex; align-items: center; justify-content: center;
    background: linear-gradient(160deg, var(--navy) 0%, var(--navy-dark) 70%);
    font-family: 'Poppins', 'Segoe UI', Arial, sans-serif;
    color: #fff; padding: 24px;
  }
  .card { max-width: 420px; width: 100%; text-align: center; }
  .seal { width: 88px; height: 88px; border-radius: 50%; background: #fff; padding: 8px;
          box-shadow: 0 0 0 3px rgba(255,152,0,0.9); margin-bottom: 20px; }
  h1 { font-size: 26px; margin: 0 0 4px; letter-spacing: 0.5px; }
  .sub { font-size: 13px; color: #C9D6F5; margin: 0 0 28px; line-height: 1.5; }
  .links { display: flex; flex-direction: column; gap: 12px; }
  a.btn {
    display: block; padding: 14px 18px; border-radius: 10px; text-decoration: none;
    font-weight: 600; font-size: 15px; transition: transform .1s ease;
  }
  a.btn:active { transform: scale(0.98); }
  .btn-primary { background: var(--orange); color: #1B2027; }
  .btn-secondary { background: rgba(255,255,255,0.08); color: #fff; border: 1px solid rgba(255,255,255,0.35); }
  footer { margin-top: 28px; font-size: 11px; color: #93A2C7; }
</style>
</head>
<body>
  <div class="card">
    <img class="seal" src="admin/assets/img/brgy-183-seal.png" alt="Barangay 183 seal">
    <h1>SmartSumbong</h1>
    <p class="sub">Localized complaint mapping for Barangay 183, Pasay City.</p>
    <div class="links">
      <a class="btn btn-primary" href="admin/login.php">Barangay Admin Login</a>
    </div>
    <footer>Capstone project &middot; Group 12 &middot; Barangay 183, Pasay City</footer>
  </div>
</body>
</html>
