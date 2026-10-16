<?php
/**
 * Builds admin/assets/data/safe-b183.json: the safe points (schools, halls, shelters, clinics, fire and police, hydrants)
 * within about 1.6 km of the Barangay 183 hall, from OpenStreetMap through Overpass, in the same shape layers.php
 * serves. The Workspace's Evacuation centres widget reads this file because the public Overpass servers are often too
 * slow for a page to wait on (35 to 42 seconds on 17 Oct 2026). Run it again when the map around the barangay changes:
 *
 *   php tools/build_safe.php
 */
declare(strict_types=1);

require __DIR__ . '/../admin/includes/hazards.php';      // HZ_LAT, HZ_LNG
require __DIR__ . '/../admin/includes/osm_layers.php';

$box = [round(HZ_LNG - 0.015, 3), round(HZ_LAT - 0.015, 3), round(HZ_LNG + 0.015, 3), round(HZ_LAT + 0.015, 3)];
$fc = osm_layer('safe', $box, 120);
if ($fc === null || !$fc['features']) {
    fwrite(STDERR, "Overpass did not answer; nothing written.\n");
    exit(1);
}
$fc['built'] = gmdate('c');
$fc['box'] = $box;
$out = __DIR__ . '/../admin/assets/data/safe-b183.json';
file_put_contents($out, json_encode($fc, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
echo count($fc['features']), ' safe points written to ', realpath($out), "\n";
