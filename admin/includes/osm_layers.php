<?php
/**
 * Map layers from OpenStreetMap through Overpass (moved here from layers.php, 17 Oct 2026, so the Workspace's
 * Evacuation centres widget reads the same safe points the map draws). See layers.php for what each layer holds.
 * Each answer is kept a week; an older answer is served when Overpass does not answer. Each safe point carries its
 * OSM element ("node/123") so safe_point_notes (0132) can add capacity and status to it.
 */
declare(strict_types=1);

/**
 * @param 'safe'|'transit' $kind
 * @param array{0:float,1:float,2:float,3:float} $box west, south, east, north (already checked by the caller)
 * @param int $timeout seconds per Overpass server (the page waits on this; tools/build_safe.php allows longer)
 * @return array{type:string, features:list<array>}|null null when Overpass did not answer and nothing is kept
 */
function osm_layer(string $kind, array $box, int $timeout = 22): ?array
{
    [$w, $s, $e, $n] = $box;
    // v3 (17 Oct 2026): safe points carry their OSM element id
    $cache = sys_get_temp_dir() . '/ss-layer-' . md5("v3|$kind|$w|$s|$e|$n") . '.json';
    $fresh = is_file($cache) && filemtime($cache) > time() - 7 * 86400;
    if ($fresh) {
        $hit = json_decode((string) file_get_contents($cache), true);
        if (is_array($hit)) return $hit;
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
    foreach (['https://overpass-api.de/api/interpreter', 'https://overpass.openstreetmap.fr/api/interpreter', 'https://overpass.private.coffee/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'] as $url) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => http_build_query(['data' => $query]),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_HTTPHEADER     => ['User-Agent: SmartSumbong/1.0 (Barangay 183 admin portal; map layers)'],
        ]);
        $raw  = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $data = is_string($raw) && $code === 200 ? json_decode($raw, true) : null;
        if (is_array($data) && isset($data['elements'])) break;
    }
    if (!is_array($data) || !isset($data['elements'])) {
        // An older answer beats none (this one's, or the layout before it carried the extras).
        $v2     = sys_get_temp_dir() . '/ss-layer-' . md5("v2|$kind|$w|$s|$e|$n") . '.json';
        $legacy = sys_get_temp_dir() . '/ss-layer-' . md5("$kind|$w|$s|$e|$n") . '.json';
        foreach ([$cache, $v2, $legacy] as $old) {
            if (is_file($old) && is_array($hit = json_decode((string) file_get_contents($old), true))) return $hit;
        }
        return null;
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
            if (!$k) continue;
            $addr = trim(implode(' ', array_filter([$t['addr:housenumber'] ?? '', $t['addr:street'] ?? ''])));
            $area = trim(implode(', ', array_filter([$t['addr:suburb'] ?? '', $t['addr:city'] ?? ''])));
            $features[] = $point($lng, $lat, [
                'id' => ($el['type'] ?? 'node') . '/' . ($el['id'] ?? 0),
                'k' => $k, 'name' => $name, 'sub' => $am ?: ($t['emergency'] ?? ''),
                'addr' => trim($addr . ($addr && $area ? ', ' : '') . $area),
                'phone' => (string) ($t['phone'] ?? $t['contact:phone'] ?? ''),
                'hours' => (string) ($t['opening_hours'] ?? ''),
                'cap'   => (string) ($t['capacity'] ?? ''),
                'op'    => (string) ($t['operator'] ?? ''),
                'web'   => preg_match('#^https?://#i', (string) ($t['website'] ?? $t['contact:website'] ?? '')) ? (string) ($t['website'] ?? $t['contact:website']) : '',
                'speciality' => (string) ($t['healthcare:speciality'] ?? ''),
            ]);
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

    $fc = ['type' => 'FeatureCollection', 'features' => $features];
    @file_put_contents($cache, json_encode($fc, JSON_UNESCAPED_UNICODE));
    return $fc;
}
