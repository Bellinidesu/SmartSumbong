<?php
// Test site only (tests/browser/serve.sh copies this beside a throwaway copy of admin/; it is never in the image):
// every request is signed in as the fake Supabase's demo administrator, so the pages can be opened without a password.
require_once __DIR__ . '/admin/includes/auth.php';
// A way to look at the portal as each rung from a browser (12 Nov 2026): /admin/__as?tier=committee&committee=peace_order&theme=dark&to=home.php
// sets the tier and committee cookies, the theme the portal remembers, and goes to the page. (The DEV menu here only changes a banner: this fake takes the rung from the cookie.)
if (str_ends_with((string) parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH), '/__as')) {
    $tier = in_array($_GET['tier'] ?? '', ['super', 'committee', 'moderator', 'captain'], true) ? $_GET['tier'] : 'super';
    $com = preg_match('/^[a-z_]+$/', $_GET['committee'] ?? '') ? $_GET['committee'] : '';
    $theme = in_array($_GET['theme'] ?? '', ['light', 'dark'], true) ? $_GET['theme'] : 'light';
    $to = preg_match('/^[a-z-]+\.php$/', $_GET['to'] ?? '') ? $_GET['to'] : ($tier === 'super' || $tier === 'captain' ? 'dashboard.php' : 'home.php');
    setcookie('ss_tier', $tier, 0, '/'); setcookie('ss_committee', $com, $com === '' ? 1 : 0, '/');
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><title>Switching</title><script>try{localStorage.setItem("ss-theme","' . $theme . '")}catch(e){}location.replace("' . $to . '")</script>';
    exit;
}
session_start_once();
if (!str_contains($_SERVER['REQUEST_URI'] ?? '', 'login.php')) {
    $_SESSION[SESSION_KEY] = ['access_token' => 'fake', 'refresh_token' => 'fake', 'expires_at' => time() + 3000,
        'id' => 'a0000000-0000-0000-0000-000000000001', 'full_name' => 'Reyes, Marites', 'email' => 'sec@brgy183.test',
        'must_change' => false, 'avatar_url' => null, 'seen' => time(),
        // 0145: the tests choose the tier with a cookie (super unless told otherwise)
        'admin_tier' => in_array($_COOKIE['ss_tier'] ?? '', ['super', 'committee', 'moderator', 'captain'], true) ? $_COOKIE['ss_tier'] : 'super',
        'committee' => preg_match('/^[a-z_]+$/', $_COOKIE['ss_committee'] ?? '') ? $_COOKIE['ss_committee'] : null,
        'is_dev' => true, 'access_at' => time()];
}
return false;
