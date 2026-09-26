<?php
/**
 * Street labels for complaints that have none yet (branch B, 0068).
 *
 * The resident app saves "Harvard Street, Villamor" right after filing;
 * complaints filed before that, or whose phone could not reach the
 * lookup, are labelled here instead — a few at a time, whenever an admin
 * has the portal open (layout_foot() calls this in the background).
 *
 * OpenStreetMap's Nominatim allows about one request a second from an
 * identified client, so this labels at most BATCH complaints per call,
 * one second apart, and reports whether any are still waiting. The
 * label rule matches ReverseGeocode.label() in the resident app.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';

header('Content-Type: application/json');

$admin = current_admin();
if (!$admin || $_SERVER['REQUEST_METHOD'] !== 'POST' || !csrf_check($_POST['csrf'] ?? null)) {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}
// The session is only read above; releasing it lets the admin's other
// requests through while this waits on the lookup.
session_write_close();

const GEOCODE_BATCH = 3;

function street_label(float $lat, float $lng): ?string
{
    $url = 'https://nominatim.openstreetmap.org/reverse?' . http_build_query([
        'format' => 'jsonv2', 'lat' => $lat, 'lon' => $lng, 'zoom' => 17, 'addressdetails' => 1,
    ]);
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_HTTPHEADER     => [
            'User-Agent: SmartSumbong/1.0 (Barangay 183 admin portal; complaint street labels)',
            'Accept-Language: en',
        ],
    ]);
    $raw = curl_exec($ch);
    if (!is_string($raw) || (int) curl_getinfo($ch, CURLINFO_HTTP_CODE) !== 200) {
        return null;
    }
    $a = json_decode($raw, true)['address'] ?? [];
    $first = static function (array $keys) use ($a): ?string {
        foreach ($keys as $k) {
            $v = trim((string) ($a[$k] ?? ''));
            if ($v !== '') return $v;
        }
        return null;
    };
    $street = $first(['road', 'pedestrian', 'footway']);
    $area   = $first(['neighbourhood', 'quarter', 'suburb']);
    if ($street === null) return $area;
    return ($area === null || $area === $street) ? $street : "{$street}, {$area}";
}

$db = db();
try {
    $rows = $db->select('reports', [
        'select'         => 'id,latitude,longitude',
        'location_label' => 'is.null',
        'deleted_at'     => 'is.null',
        'order'          => 'created_at.desc',
        'limit'          => (string) (GEOCODE_BATCH + 1),
    ]);
} catch (SupabaseError $ex) {
    echo json_encode(['error' => safe_error($ex)]);
    exit;
}

$labelled = 0;
foreach (array_slice($rows, 0, GEOCODE_BATCH) as $i => $r) {
    if ($i > 0) sleep(1);
    $label = street_label((float) $r['latitude'], (float) $r['longitude']);
    if ($label === null) continue;
    try {
        $db->rpc('set_report_location_label', ['p_report' => $r['id'], 'p_label' => $label]);
        $labelled++;
    } catch (SupabaseError) {
        // Left for the next call.
    }
}

echo json_encode(['labelled' => $labelled, 'more' => count($rows) > GEOCODE_BATCH]);
