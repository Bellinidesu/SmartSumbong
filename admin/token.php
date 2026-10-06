<?php
/**
 * A fresh access token for the page's live connections (realtime and the
 * quiet polls). Each page is handed the token it was loaded with, and a
 * Supabase token lasts an hour: a Residents list left open past that kept
 * polling with an expired one, failed quietly, and stopped showing new
 * registrations (Rose, 27 Sep 2026). layout.php's ssAccessToken() asks
 * here before the page's token runs out.
 *
 * Renews early — with 15 minutes left rather than require_admin()'s 60
 * seconds — so a page asking every few minutes never holds a stale one.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';

header('Content-Type: application/json');
header('Cache-Control: no-store');

$admin = current_admin();
if (!$admin || session_idle_expired($admin)) {
    http_response_code(401);
    echo json_encode(['error' => 'signed_out']);
    exit;
}

if ($admin['expires_at'] < time() + 15 * 60) {
    try {
        $fresh = Supabase::refresh($admin['refresh_token']);
        $admin['access_token']  = $fresh['access_token'];
        $admin['refresh_token'] = $fresh['refresh_token'] ?? $admin['refresh_token'];
        $admin['expires_at']    = time() + (int) ($fresh['expires_in'] ?? 3600);
        $_SESSION[SESSION_KEY]  = $admin;
    } catch (SupabaseError) {
        http_response_code(401);
        echo json_encode(['error' => 'signed_out']);
        exit;
    }
}

echo json_encode(['token' => $admin['access_token'], 'expires_at' => $admin['expires_at']]);
