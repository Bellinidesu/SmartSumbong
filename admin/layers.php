<?php
/**
 * Map layers for Spatial Distribution (Bellinist phase 4, 9 Oct 2026).
 *
 * Safe points (hydrants, clinics, schools and halls that can shelter
 * people, the barangay hall, fire and police) and public transport (the
 * jeepney and bus routes and their stops) come from OpenStreetMap through
 * Overpass. The browser does not call Overpass itself: the portal's
 * content-security policy lists the few hosts it may talk to, and this
 * keeps it that way. The answer is kept for a week, because the map under
 * it changes about as often as the streets do.
 *
 *   layers.php?k=safe|transit&b=west,south,east,north
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';

header('Content-Type: application/json');
header('Cache-Control: private, max-age=3600');

if (!current_admin() || $_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}
session_write_close();

$kind = (string) ($_GET['k'] ?? '');
$box  = array_map('floatval', explode(',', (string) ($_GET['b'] ?? '')));
if (!in_array($kind, ['safe', 'transit'], true) || count($box) !== 4) {
    http_response_code(400);
    echo json_encode(['error' => 'bad request']);
    exit;
}
[$w, $s, $e, $n] = array_map(static fn (float $v): float => round($v, 3), $box);
// Only boxes the size of a barangay, and only around the Philippines.
if ($e <= $w || $n <= $s || ($e - $w) > 0.06 || ($n - $s) > 0.06 || $w < 116 || $e > 127 || $s < 4 || $n > 22) {
    http_response_code(400);
    echo json_encode(['error' => 'bad box']);
    exit;
}

// The jeepney and bus routes through the barangay are served from a file in the portal (assets/data/transit-b183.json, built by tools/build_transit.py):
// the public Overpass servers are often down or too slow, and the full answer is over 12 MB, so a live call left the layer empty. The file is
// every route's road once, with the routes that use it (a few hundred lines, 13 KB zipped). The live query below stays as the fallback.
if ($kind === 'transit' && is_file(__DIR__ . '/assets/data/transit-b183.json')) {
    header('Cache-Control: private, max-age=86400');
    readfile(__DIR__ . '/assets/data/transit-b183.json');
    exit;
}

require_once __DIR__ . '/includes/osm_layers.php';

$fc = osm_layer($kind, [$w, $s, $e, $n]);
if ($fc === null) {
    http_response_code(502);
    echo json_encode(['error' => 'OpenStreetMap did not answer']);
    exit;
}
echo json_encode($fc, JSON_UNESCAPED_UNICODE);
