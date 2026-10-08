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

$cache = sys_get_temp_dir() . '/ss-layer-' . md5("$kind|$w|$s|$e|$n") . '.json';
$fresh = is_file($cache) && filemtime($cache) > time() - 7 * 86400;
if ($fresh) {
    readfile($cache);
    exit;
}

$bb = "$s,$w,$n,$e";
$query = $kind === 'safe'
    ? "[out:json][timeout:25];(node[emergency=fire_hydrant]($bb);node[emergency=assembly_point]($bb);"
      . "nwr[amenity~\"^(hospital|clinic|doctors|fire_station|police|townhall|community_centre|social_facility|school|shelter)\$\"]($bb);"
      . "nwr[leisure~\"^(sports_hall|sports_centre)\$\"]($bb);nwr[office=government]($bb););out center tags;"
    : "[out:json][timeout:25];(relation[type=route][route~\"^(bus|share_taxi|jeepney|trolleybus|tram|train|light_rail|subway)\$\"]($bb);)"
      . ";out geom($bb);(node[highway=bus_stop]($bb);node[public_transport=platform]($bb););out;";

// The public Overpass servers are shared and sometimes busy: try each in
// turn, and ask for the geometry only inside the box.
$data = null;
foreach (['https://overpass-api.de/api/interpreter', 'https://overpass.private.coffee/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'] as $url) {
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => http_build_query(['data' => $query]),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 22,
        CURLOPT_HTTPHEADER     => ['User-Agent: SmartSumbong/1.0 (Barangay 183 admin portal; map layers)'],
    ]);
    $raw  = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $data = is_string($raw) && $code === 200 ? json_decode($raw, true) : null;
    if (is_array($data) && isset($data['elements'])) break;
}
if (!is_array($data) || !isset($data['elements'])) {
    // A week-old answer beats none.
    if (is_file($cache)) { readfile($cache); exit; }
    http_response_code(502);
    echo json_encode(['error' => 'OpenStreetMap did not answer']);
    exit;
}

$features = [];
$point = static fn (float $lng, float $lat, array $p): array => [
    'type' => 'Feature', 'properties' => $p, 'geometry' => ['type' => 'Point', 'coordinates' => [$lng, $lat]],
];

if ($kind === 'safe') {
    foreach ($data['elements'] as $el) {
        $t = $el['tags'] ?? [];
        $lat = (float) ($el['lat'] ?? $el['center']['lat'] ?? 0);
        $lng = (float) ($el['lon'] ?? $el['center']['lon'] ?? 0);
        if (!$lat || !$lng) continue;
        $am = $t['amenity'] ?? ''; $name = trim((string) ($t['name'] ?? ''));
        $k = null;
        if (($t['emergency'] ?? '') === 'fire_hydrant')            $k = 'hydrant';
        elseif (($t['emergency'] ?? '') === 'assembly_point')      $k = 'evac';
        elseif (in_array($am, ['hospital', 'clinic', 'doctors'], true)) $k = 'health';
        elseif (in_array($am, ['fire_station', 'police'], true))   $k = 'responder';
        elseif ($am === 'townhall' || (($t['office'] ?? '') === 'government' && stripos($name, 'barangay') !== false)) $k = 'hall';
        elseif (in_array($am, ['school', 'community_centre', 'social_facility', 'shelter'], true)
                || in_array($t['leisure'] ?? '', ['sports_hall', 'sports_centre'], true)) $k = 'evac';
        if ($k) $features[] = $point($lng, $lat, ['k' => $k, 'name' => $name, 'sub' => $am ?: ($t['emergency'] ?? '')]);
    }
} else {
    $seen = [];
    foreach ($data['elements'] as $el) {
        $t = $el['tags'] ?? [];
        if (($el['type'] ?? '') === 'relation') {
            $lines = [];
            foreach ($el['members'] ?? [] as $m) {
                if (($m['type'] ?? '') !== 'way' || empty($m['geometry'])) continue;
                $lines[] = array_map(static fn (array $g): array => [(float) $g['lon'], (float) $g['lat']], $m['geometry']);
            }
            if (!$lines) continue;
            $features[] = [
                'type' => 'Feature',
                'properties' => ['k' => 'route', 'ref' => (string) ($t['ref'] ?? ''), 'name' => (string) ($t['name'] ?? ''),
                                 'mode' => (string) ($t['route'] ?? ''), 'from' => (string) ($t['from'] ?? ''), 'to' => (string) ($t['to'] ?? '')],
                'geometry' => ['type' => 'MultiLineString', 'coordinates' => $lines],
            ];
        } elseif (($el['type'] ?? '') === 'node' && isset($el['lat'], $el['lon'])) {
            $key = round((float) $el['lat'], 5) . ',' . round((float) $el['lon'], 5);
            if (isset($seen[$key])) continue;
            $seen[$key] = true;
            $features[] = $point((float) $el['lon'], (float) $el['lat'], ['k' => 'stop', 'name' => (string) ($t['name'] ?? '')]);
        }
    }
}

$out = json_encode(['type' => 'FeatureCollection', 'features' => $features], JSON_UNESCAPED_UNICODE);
@file_put_contents($cache, $out);
echo $out;
