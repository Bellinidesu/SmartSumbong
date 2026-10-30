<?php
// Test site only (tests/browser/serve.sh copies this beside a throwaway copy of admin/; it is never in the image):
// every request is signed in as the fake Supabase's demo administrator, so the pages can be opened without a password.
require_once __DIR__ . '/admin/includes/auth.php';
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
