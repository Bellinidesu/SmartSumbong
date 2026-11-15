<?php
/**
 * The public "At a glance" feed for the sign-in pages (15 Nov 2026): weather, the PAGASA warning, the flood advisory, the barangay's public hotlines and two
 * Pasay headlines. No sign-in needed and nothing of the barangay's own data in it; see includes/glance.php. The browser asks for it once the page is
 * drawn and again every five minutes while the tab is open; the server keeps each source five to ten minutes, so this costs the sources almost nothing.
 *
 *   glance.php   ->  {ok, at, phase, when, now{temp,feels,wind,kind}|null, warn|null, flood|null, hot[], news[]}
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/glance.php';

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    http_response_code(405);
    header('Allow: GET');
    echo json_encode(['ok' => false]);
    exit;
}
header('Cache-Control: public, max-age=120');

try {
    echo json_encode(glance_read(), JSON_UNESCAPED_UNICODE);
} catch (Throwable) {
    http_response_code(200);   // the panel simply shows what it can without it
    echo json_encode(['ok' => false]);
}
