<?php
/**
 * What PAGASA and GDACS say right now about Barangay 183 (17 Oct 2026). Read by hazards.php for the Spatial
 * Distribution cards and by the Workspace widgets (Flood watch, Typhoon watch, the alarm); see hazards.php for the
 * sources and their limits. Kept ten minutes, with the last good copy served (marked stale) when every source fails.
 */
declare(strict_types=1);

const HZ_LAT = 14.5194, HZ_LNG = 121.0122;      // Barangay 183
const HZ_TTL = 600;                              // ten minutes

/** GET or POST a URL; null on any failure. */
function hz_fetch(string $url, bool $post = false): ?string
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_CONNECTTIMEOUT => 4,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS      => 2,
        CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
        CURLOPT_USERAGENT      => 'SmartSumbong-Barangay183/1.0 (barangay disaster desk)',
        CURLOPT_HTTPHEADER     => $post ? [
            'X-Requested-With: XMLHttpRequest',
            'Origin: https://bagong.pagasa.dost.gov.ph',
            'Referer: https://bagong.pagasa.dost.gov.ph/',
            'Accept: application/json, text/javascript, */*; q=0.01',
        ] : ['Accept: application/json, application/xml, text/xml, */*'],
    ]);
    if ($post) {
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, '');
    }
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    return ($body !== false && $code === 200 && $body !== '') ? (string) $body : null;
}

/**
 * Fetches several addresses at once and returns each body (or null) under its key. PAGASA and GDACS used to be asked one
 * after another, which took close to ten seconds when GDACS was slow; asked together it is as long as the slowest.
 *
 * @param array<string, array{0:string, 1:bool, 2?:int}> $jobs key => [url, post, seconds before giving up]
 * @return array<string, ?string>
 */
function hz_fetch_many(array $jobs, int $timeout = 7): array
{
    $mh = curl_multi_init();
    $hs = [];
    foreach ($jobs as $k => [$url, $post, $to]) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $to ?? $timeout,
            CURLOPT_CONNECTTIMEOUT => 4,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS      => 2,
            CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
            CURLOPT_REDIR_PROTOCOLS => CURLPROTO_HTTPS,
            CURLOPT_ENCODING       => '',
            CURLOPT_USERAGENT      => 'SmartSumbong-Barangay183/1.0 (barangay disaster desk)',
            CURLOPT_HTTPHEADER     => $post ? [
                'X-Requested-With: XMLHttpRequest',
                'Origin: https://bagong.pagasa.dost.gov.ph',
                'Referer: https://bagong.pagasa.dost.gov.ph/',
                'Accept: application/json, text/javascript, */*; q=0.01',
            ] : ['Accept: application/json, application/xml, text/xml, */*'],
        ]);
        if ($post) {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, '');
        }
        curl_multi_add_handle($mh, $ch);
        $hs[$k] = $ch;
    }
    do {
        $st = curl_multi_exec($mh, $active);
        if ($active) {
            curl_multi_select($mh, 0.3);
        }
    } while ($active && $st === CURLM_OK);
    $out = [];
    foreach ($hs as $k => $ch) {
        $body = curl_multi_getcontent($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $out[$k] = ($code === 200 && is_string($body) && $body !== '') ? $body : null;
        curl_multi_remove_handle($mh, $ch);
    }
    curl_multi_close($mh);
    return $out;
}

function hz_km(float $lat1, float $lng1, float $lat2, float $lng2): float
{
    $r = 6371.0; $p = M_PI / 180;
    $a = sin(($lat2 - $lat1) * $p / 2) ** 2 + cos($lat1 * $p) * cos($lat2 * $p) * sin(($lng2 - $lng1) * $p / 2) ** 2;
    return 2 * $r * asin(min(1.0, sqrt($a)));
}

function hz_dir(float $lat1, float $lng1, float $lat2, float $lng2): string
{
    $y = sin(($lng2 - $lng1) * M_PI / 180) * cos($lat2 * M_PI / 180);
    $x = cos($lat1 * M_PI / 180) * sin($lat2 * M_PI / 180) - sin($lat1 * M_PI / 180) * cos($lat2 * M_PI / 180) * cos(($lng2 - $lng1) * M_PI / 180);
    $b = fmod(rad2deg(atan2($y, $x)) + 360, 360);
    return ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][(int) round($b / 45) % 8];
}

/** PAGASA's Metro Manila regional desk (NCR PRSD): its own rainfall and thunderstorm advisories. */
const HZ_NCR_PAGE = 'https://www.pagasa.dost.gov.ph/regional-forecast/ncrprsd';

/**
 * The NCR desk's page read for its two advisory tabs (21 Oct 2026). The page's layout (the #rainfalls and
 * #thunderstorms tabs, one <div> per advisory, newest first) was found by jakewarren/pagasa-feeds (MIT), which
 * turns it into RSS; it is read here directly, so it is as fresh as PAGASA's page. A thunderstorm advisory covers
 * the next two hours or so; it counts as current for three hours from its issue time.
 *
 * @return ?array{rain:?string, thunder:?array{no:?int, issued:?string, current:bool, metro:bool, pasay:bool, places:string, text:string}, url:string}
 */
function hz_ncr(?string $html, int $now): ?array
{
    if ($html === null) {
        return null;
    }
    $tab = static function (string $id, string $next) use ($html): ?array {
        $a = strpos($html, 'id="' . $id . '"');
        if ($a === false) {
            return null;
        }
        $b = strpos($html, 'id="' . $next . '"', $a);
        $part = substr($html, $a, $b === false ? 8000 : $b - $a);
        preg_match_all('#<div>(.*?)</div>#s', $part, $m);
        return array_values(array_filter(array_map(static function (string $x): string {
            $x = preg_replace('#<br\s*/?>#i', "\n", $x) ?? '';
            $x = html_entity_decode(strip_tags($x), ENT_QUOTES | ENT_HTML5);
            $lines = array_map(static fn ($l) => trim((string) preg_replace('/[ \t\x{00A0}]+/u', ' ', $l)), explode("\n", $x));
            return trim(implode("\n", array_filter($lines, static fn ($l) => $l !== '')));
        }, $m[1])));
    };
    $rains = $tab('rainfalls', 'thunderstorms');
    $storms = $tab('thunderstorms', 'special-forecasts');
    if ($rains === null && $storms === null) {
        return null;   // the page changed or did not load: not the same as "no advisory"
    }
    $rain = $rains[0] ?? null;
    if ($rain !== null && preg_match('/no\s+heavy\s+rainfall\s+warning/i', $rain)) {
        $rain = null;
    }
    $thunder = null;
    if (!empty($storms[0])) {
        $t = $storms[0];
        $issued = null;
        if (preg_match('/Issued at:\s*(\d{1,2}:\d{2}\s*[AP]M),\s*(\d{1,2}\s+[A-Za-z]+\s+\d{4})/i', $t, $m)) {
            $d = DateTimeImmutable::createFromFormat('!j F Y g:i A', $m[2] . ' ' . strtoupper(preg_replace('/\s+/', ' ', $m[1])), new DateTimeZone('Asia/Manila'));
            $issued = $d ? $d->getTimestamp() : null;
        }
        // "Metro Manila (Caloocan, Quezon City, ...)" names cities; "Metro Manila" alone is the whole region
        $places = preg_match('/Metro Manila\s*\(([^)]*)\)/i', $t, $mm) ? trim($mm[1]) : '';
        $metro = (bool) preg_match('/\bMetro Manila\b/i', $t);
        $thunder = [
            'no'      => preg_match('/Advisory\s+No\.?\s*(\d+)/i', $t, $mn) ? (int) $mn[1] : null,
            'issued'  => $issued ? gmdate('c', $issued) : null,
            'current' => $issued !== null && $now - $issued <= 3 * 3600 && $issued <= $now + 600,
            'metro'   => $metro,
            'pasay'   => $metro && ($places === '' || (bool) preg_match('/\bPasay\b/i', $places)),
            'places'  => mb_substr($places, 0, 160),
            'text'    => mb_substr($t, 0, 700),
        ];
    }
    return ['rain' => $rain !== null ? mb_substr($rain, 0, 700) : null, 'thunder' => $thunder, 'url' => HZ_NCR_PAGE];
}

/** A tropical cyclone wind signal block in PAGASA's ActiveWarning: its blocks carry class tcws1..tcws5. */
function hz_is_tcws(string $type, array $bySeverity): bool
{
    if ($type === 'Tropical Cyclone Alert') {
        return true;
    }
    foreach ($bySeverity as $block) {
        if (is_array($block) && preg_match('/^tcws[1-5]$/', (string) ($block['class'] ?? ''))) {
            return true;
        }
    }
    return false;
}

/**
 * The signal over Metro Manila and the highest one anywhere, from one or more storms' tcws blocks.
 * @return array{metro:?int, top:?array{n:int, areas:string}}
 */
function hz_signals(array $storms): array
{
    $metro = null; $top = null;
    foreach ($storms as $bySeverity) {
        foreach ((array) $bySeverity as $sevKey => $block) {
            $n = preg_match('/^tcws([1-5])$/', (string) ($block['class'] ?? ''), $m) ? (int) $m[1]
               : (preg_match('/^([1-5])\b/', (string) $sevKey, $m) ? (int) $m[1] : 0);
            if (!$n) {
                continue;
            }
            $areas = [];
            foreach ((array) ($block['regions'] ?? []) as $region => $r) {
                $a = trim(preg_replace('/\s+/', ' ', (string) ($r['areas'] ?? '')) ?? '');
                $areas[] = $a !== '' ? $a : trim((string) $region);
                if (preg_match('/\b(NCR|National Capital|Metro Manila|Pasay)\b/i', $region . ' ' . $a)) {
                    $metro = max($metro ?? 0, $n);
                }
            }
            if ($areas && (!$top || $n > $top['n'])) {
                $top = ['n' => $n, 'areas' => mb_substr(implode(', ', $areas), 0, 120)];
            }
        }
    }
    return ['metro' => $metro, 'top' => $top];
}

/** @return array{ok:bool, at:string, stale:bool, warnings:list<array>, cyclone:?array, forecast:list<array>, sources:array} */
function hazards_read(): array
{
    $cache = sys_get_temp_dir() . '/ss-hazards-v2.json';
    if (is_file($cache) && filemtime($cache) > time() - HZ_TTL) {
        $hit = json_decode((string) file_get_contents($cache), true);
        if (is_array($hit)) {
            return $hit;
        }
    }

    $B = hz_fetch_many([
        'aw'   => ['https://bagong.pagasa.dost.gov.ph/api/ActiveWarning', true, null],
        'ct'   => ['https://bagong.pagasa.dost.gov.ph/api/CycloneTrack', true, null],
        'gd'   => ['https://www.gdacs.org/xml/rss.xml', false, 4],      // the slow one: 4 s, then the last copy it gave
        'mg0'  => ['https://bagong.pagasa.dost.gov.ph/api/meteogram/425/0', false, null],
        'mg1'  => ['https://bagong.pagasa.dost.gov.ph/api/meteogram/425/1', false, null],
        'ncr'  => [HZ_NCR_PAGE, false, 6],
    ]);
    // GDACS answers in 3 to 9 seconds; its last good copy (up to six hours old) stands in when it is slow
    $gdFile = sys_get_temp_dir() . '/ss-gdacs-v1.xml';
    if ($B['gd'] !== null) {
        @file_put_contents($gdFile, $B['gd'], LOCK_EX);
    } elseif (is_file($gdFile) && filemtime($gdFile) > time() - 6 * 3600) {
        $B['gd'] = (string) file_get_contents($gdFile);
    }

    $sources = ['pagasa_warnings' => false, 'pagasa_cyclone' => false, 'pagasa_forecast' => false, 'gdacs' => false, 'pagasa_ncr' => false];
    $out     = ['ok' => true, 'at' => gmdate('c'), 'stale' => false, 'warnings' => [], 'cyclone' => null, 'forecast' => [], 'sources' => []];

    // ---- PAGASA: the warnings that touch Metro Manila -------------------------------------------
    $raw = $B['aw'];
    $aw  = $raw !== null ? json_decode($raw, true) : null;
    $tcws = [];   // the wind signals, read apart from the rain and flood warnings
    if (is_array($aw)) {
        $sources['pagasa_warnings'] = true;
        foreach ($aw as $type => $bySeverity) {
            if (!is_array($bySeverity)) {
                continue;
            }
            // A storm comes keyed by its own name ("Super Typhoon Rosal (CHAMPI)"), one block per signal
            // number, each with class tcws1 to tcws5. It is a wind signal, not a rain warning.
            if (hz_is_tcws((string) $type, $bySeverity)) {
                $tcws[(string) $type] = $bySeverity;
                continue;
            }
            foreach ($bySeverity as $sevKey => $block) {
                foreach ((array) ($block['regions'] ?? []) as $region => $r) {
                    $where = $region . ' ' . ($r['areas'] ?? '');
                    if (!preg_match('/\b(NCR|National Capital|Metro Manila|Pasay|Manila|Rizal|Bulacan|Cavite|Region IV-A|Region 4-A|CALABARZON|Central Luzon|Region 3)\b/i', $where)) {
                        continue;
                    }
                    // Only the warnings that name the capital region or its neighbours are shown; the
                    // flag says whether Metro Manila itself is named.
                    $metro = (bool) preg_match('/\b(NCR|National Capital|Metro Manila|Pasay)\b/i', $where);
                    $sev = strtolower((string) $sevKey);
                    $level = str_contains($sev, 'red') ? 3 : (str_contains($sev, 'orange') ? 2 : (str_contains($sev, 'yellow') ? 1 : 0));
                    $desc = trim(html_entity_decode(strip_tags(str_replace(['<br />', '<br/>', '<br>'], ' ', (string) ($r['description'] ?? '')))));
                    $desc = preg_replace('/\s+/', ' ', $desc) ?? '';
                    $out['warnings'][] = [
                        'type'    => (string) $type,
                        'severity' => (string) preg_replace('/^\d+/', '', (string) $sevKey),
                        'level'   => $level,
                        'metro'   => $metro,
                        'region'  => (string) $region,
                        'areas'   => mb_substr((string) ($r['areas'] ?? ''), 0, 160),
                        'issued'  => (string) ($r['issued_at'] ?? ''),
                        'expires' => (string) ($r['expired_at'] ?? ''),
                        'text'    => mb_substr($desc, 0, 320),
                        'url'     => preg_match('#^https://(www\.)?panahon\.gov\.ph/#', (string) ($r['url'] ?? '')) ? (string) $r['url'] : '',
                    ];
                }
            }
        }
    }

    // ---- PAGASA: cyclone tracks; a cyclone is current if its track has a point in the last day --
    $raw = $B['ct'];
    $ct  = $raw !== null ? json_decode($raw, true) : null;
    $tz  = new DateTimeZone('Asia/Manila');
    if (is_array($ct)) {
        $sources['pagasa_cyclone'] = true;
        $now = time();
        foreach ($ct as $track) {
            $pts = (array) ($track['info'] ?? []);
            if (!$pts) {
                continue;
            }
            ksort($pts);
            $last = null; $nowPt = null; $future = 0;
            foreach ($pts as $k => $p) {
                $ts = (new DateTimeImmutable((string) $k, $tz))->getTimestamp();
                if ($ts <= $now + 3600) { $nowPt = $p + ['ts' => $ts]; }
                if ($ts > $now) { $future++; }
                $last = $p + ['ts' => $ts];
            }
            if (!$nowPt || ($last['ts'] ?? 0) < $now - 86400) {
                continue;   // an old storm: its track stays on the website for the record
            }
            $lat = (float) $nowPt['latitude']; $lng = (float) $nowPt['longitude'];
            $out['cyclone'] = [
                'name'    => (string) ($track['cyclone_name'] ?? ''),
                'kind'    => (string) ($nowPt['cyclone_type'] ?? ''),
                'lat'     => $lat, 'lng' => $lng,
                'radius'  => (float) ($nowPt['radius'] ?? 0),
                'km'      => (int) round(hz_km(HZ_LAT, HZ_LNG, $lat, $lng)),
                'dir'     => hz_dir(HZ_LAT, HZ_LNG, $lat, $lng),
                'asof'    => gmdate('c', (int) $nowPt['ts']),
                'path'    => array_values(array_map(static fn ($p) => [(float) $p['latitude'], (float) $p['longitude']], $pts)),
                'ahead'   => $future,
                'signal'  => null,
            ];
            break;
        }
    }

    // ---- PAGASA: the wind signals: the one over Metro Manila, and the highest anywhere --------------
    // `signal` is Metro Manila's own (null when none is raised here), so the Signal 3 alarm fires only for us.
    // The storm whose name matches the track is read first; with no match, every storm's signals count.
    if ($out['cyclone'] && $tcws) {
        $mine = array_filter($tcws, static fn ($k) => $out['cyclone']['name'] !== '' && stripos($k, $out['cyclone']['name']) !== false, ARRAY_FILTER_USE_KEY) ?: $tcws;
        $sig = hz_signals($mine);
        $out['cyclone']['signal']    = $sig['metro'];
        $out['cyclone']['signalTop'] = $sig['top'];
    }

    // ---- GDACS: a second opinion on cyclones near the Philippine area of responsibility ------------
    $raw = $B['gd'];
    if ($raw !== null && ($xml = @simplexml_load_string($raw)) !== false) {
        $sources['gdacs'] = true;
        foreach ($xml->channel->item ?? [] as $it) {
            $g = $it->children('http://www.gdacs.org');
            if ((string) $g->eventtype !== 'TC' || (string) $g->iscurrent !== 'true') {
                continue;
            }
            $pt = $it->children('http://www.w3.org/2003/01/geo/wgs84_pos#')->Point;
            $lat = (float) $pt->lat; $lng = (float) $pt->long;
            if ($lat < 2 || $lat > 28 || $lng < 105 || $lng > 140 || hz_km(HZ_LAT, HZ_LNG, $lat, $lng) > 1600) {
                continue;   // the Philippine area and its surroundings only; a storm 2,000 km away is not news here
            }
            $sev = (string) $g->severity;
            $wind = preg_match('/([0-9.]+)/', $sev, $m) ? (int) round((float) $m[1]) : null;
            $name = preg_match('/cyclone\s+([A-Z0-9-]+)/i', (string) $it->title, $m) ? $m[1] : '';
            $gd = ['name' => $name, 'alert' => (string) $g->alertlevel, 'wind' => $wind, 'km' => (int) round(hz_km(HZ_LAT, HZ_LNG, $lat, $lng)), 'dir' => hz_dir(HZ_LAT, HZ_LNG, $lat, $lng)];
            if ($out['cyclone']) {
                if (strcasecmp(preg_replace('/-\d+$/', '', $name), $out['cyclone']['name']) === 0 || $gd['km'] < $out['cyclone']['km'] + 200) {
                    $out['cyclone']['gdacs'] = $gd;
                }
            } else {
                $out['cyclone'] = ['name' => $name, 'kind' => '', 'lat' => $lat, 'lng' => $lng, 'radius' => 0, 'km' => $gd['km'], 'dir' => $gd['dir'], 'asof' => gmdate('c'), 'path' => [[$lat, $lng]], 'ahead' => 0, 'signal' => null, 'gdacs' => $gd, 'onlyGdacs' => true];
            }
        }
    }

    // ---- PAGASA: the next twelve hours of rain for Port Area, Manila -------------------------------
    $from = (new DateTimeImmutable('now', $tz))->setTime((int) (new DateTimeImmutable('now', $tz))->format('G'), 0);
    $seen = [];
    foreach ([0, 1] as $dayOffset) {   // today and tomorrow, so late in the evening there are still twelve hours
        $raw = $B['mg' . $dayOffset];
        $mg  = $raw !== null ? json_decode($raw, true) : null;
        if (!is_array($mg) || !isset($mg['forecast']['tabular']['time'])) {
            continue;
        }
        $sources['pagasa_forecast'] = true;
        $out['forecastUpdated'] = (string) ($mg['meta']['lastupdate'] ?? '');
        foreach ($mg['forecast']['tabular']['time'] as $row) {
            $h = (string) ($row['@attributes']['from'] ?? '');
            if ($h === '' || isset($seen[$h]) || count($out['forecast']) >= 12) {
                continue;
            }
            $seen[$h] = true;
            try { $t = new DateTimeImmutable($h, $tz); } catch (Throwable $e) { continue; }
            if ($t < $from) {
                continue;
            }
            $out['forecast'][] = ['h' => $t->format('H:i'), 'mm' => (float) ($row['precipitation']['@attributes']['value'] ?? 0)];
        }
    }

    // ---- PAGASA's Metro Manila desk: its rainfall and thunderstorm advisories -------------------------
    $out['ncr'] = hz_ncr($B['ncr'], time());
    $sources['pagasa_ncr'] = $out['ncr'] !== null;

    $out['sources'] = $sources;

    // Keep the last good copy: if every source failed, serve the old answer, marked stale.
    if (!array_filter($sources)) {
        if (is_file($cache)) {
            $old = json_decode((string) file_get_contents($cache), true);
            if (is_array($old)) {
                $old['stale'] = true;
                return $old;
            }
        }
        $out['ok'] = false;
        return $out;
    }

    @file_put_contents($cache, json_encode($out, JSON_UNESCAPED_UNICODE), LOCK_EX);
    return $out;
}
