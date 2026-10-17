<?php
/**
 * The Workspace widgets (Ace, 17 Oct 2026: all 120 approved on the aesthetics page, sections 33 and 34).
 *
 * widget_catalogue() lists every widget with its group on the library (live, cases, team, tools, apps, rss, games,
 * me) and the data groups it reads. widgets.php answers with groups, not widgets, so two widgets that read the same
 * thing (Weather, Heat index, UV and the 24-hour strip all read 'wx') cost one call. A widget with no groups runs in
 * the page alone (calculator, dice, torch, the phrasebook).
 *
 * Groups that read the database run as the signed-in administrator (their row-level security applies) and in one
 * parallel batch. Groups that read outside sources go through includes/feeds.php: cached, last good copy kept.
 */
declare(strict_types=1);

require_once __DIR__ . '/feeds.php';
require_once __DIR__ . '/hazards.php';
require_once __DIR__ . '/osm_layers.php';

const WS_OPEN = 'in.(pending_review,validated,assigned,in_progress,offline_investigation)';
/** The twelve a new staff member starts with (Ace left the choice to me, 17 Oct 2026): the day, the work, the team, the sky. */
const WS_DEFAULT_TABS = ['brief', 'queue', 'due', 'risk', 'duty', 'req', 'flood', 'ty', 'wx', 'note', 'recent', 'eff'];
const WS_GAMES = ['ttt', 'mem', 'react', 'whack', 'hl', 'rps', 'snake', 'g2048', 'wordl', 'sudoku', 'mines', 'quiz', 'simon', 'type'];

/**
 * id => [library group, 'ready' | 'new', data groups]. 'new' marks the eleven that needed somewhere to keep what people
 * write; 0132 gave them that, so every widget is buildable now (the flag stays for the library's "new" tag).
 *
 * @return array<string, array{0:string, 1:string, 2:list<string>}>
 */
function widget_catalogue(): array
{
    $news = ['rss:philstar', 'rss:rappler', 'rss:gma', 'rss:inquirer'];
    $c = [
        // live conditions
        'brief' => ['live', 'ready', ['brief']], 'flood' => ['live', 'ready', ['hazards', 'wx']], 'ty' => ['live', 'ready', ['hazards']],
        'wx' => ['live', 'ready', ['wx']], 'heat' => ['live', 'ready', ['wx']], 'quake' => ['live', 'ready', ['quake']],
        'aq' => ['live', 'ready', ['air']], 'tide' => ['live', 'ready', ['marine']], 'sun' => ['live', 'ready', ['wx']],
        'news' => ['live', 'ready', $news], 'fuel' => ['live', 'ready', ['rss:fuel']], 'uv' => ['live', 'ready', ['wx']],
        'wind' => ['live', 'ready', ['wx']], 'hourly' => ['live', 'ready', ['wx']], 'week' => ['live', 'ready', ['wx']],
        'press' => ['live', 'ready', ['wx']], 'sea' => ['live', 'ready', ['marine']],
        // cases and numbers
        'risk' => ['cases', 'ready', ['risk']], 'queue' => ['cases', 'ready', ['queue']], 'due' => ['cases', 'ready', ['due']],
        'rec' => ['cases', 'ready', ['recur']], 'mix' => ['cases', 'ready', ['numbers']], 'pace' => ['cases', 'ready', ['numbers']],
        'street' => ['cases', 'ready', ['numbers']], 'eff' => ['cases', 'ready', ['numbers', 'sla']], 'minimap' => ['cases', 'ready', ['map']],
        'recent' => ['cases', 'ready', ['activity']], 'photos' => ['cases', 'ready', ['photos']], 'search' => ['cases', 'ready', []],
        'trend' => ['cases', 'ready', ['numbers']], 'hours' => ['cases', 'ready', ['numbers']], 'status' => ['cases', 'ready', ['numbers']],
        'sla' => ['cases', 'ready', ['sla', 'numbers']], 'escal' => ['cases', 'ready', ['numbers']], 'today' => ['cases', 'ready', ['numbers']],
        // team
        'duty' => ['team', 'ready', ['team']], 'req' => ['team', 'ready', ['team']], 'dir' => ['team', 'ready', ['team']],
        'note' => ['team', 'new', ['posts']], 'shift' => ['team', 'new', ['posts']], 'board' => ['team', 'new', ['posts']],
        'attend' => ['team', 'ready', ['team']], 'bday' => ['team', 'new', ['team']], 'poll' => ['team', 'new', ['polls']],
        'checkpt' => ['team', 'new', ['checkpoints', 'team']], 'roster' => ['team', 'ready', ['team']], 'leave' => ['team', 'new', ['team']],
        'train' => ['team', 'new', ['team']], 'bull' => ['team', 'new', ['posts']],
        // tools
        'evac' => ['tools', 'ready', ['evac']], 'hot' => ['tools', 'ready', ['hotlines']], 'links' => ['tools', 'ready', []],
        'timer' => ['tools', 'ready', []], 'cal' => ['tools', 'ready', ['holidays', 'due', 'team']], 'law' => ['tools', 'ready', []],
        'siren' => ['tools', 'ready', ['settings']], 'sms' => ['tools', 'ready', []], 'qr' => ['tools', 'ready', ['meta']],
        'forms' => ['tools', 'ready', []], 'hol' => ['tools', 'ready', ['holidays']], 'maps' => ['tools', 'ready', []],
        'donate' => ['tools', 'new', ['relief']],
        // little apps
        'calc' => ['apps', 'ready', []], 'clock' => ['apps', 'ready', ['settings']], 'torch' => ['apps', 'ready', []],
        'compass' => ['apps', 'ready', ['meta']], 'convert' => ['apps', 'ready', []], 'dice' => ['apps', 'ready', []],
        'coin' => ['apps', 'ready', []], 'pick' => ['apps', 'ready', ['team']], 'cpr' => ['apps', 'ready', []],
        'fare' => ['apps', 'ready', ['settings']], 'battery' => ['apps', 'ready', []], 'quote' => ['apps', 'ready', []],
        'talk' => ['apps', 'ready', []], 'code' => ['apps', 'ready', []], 'aid' => ['apps', 'ready', []],
        'stopw' => ['apps', 'ready', []], 'world' => ['apps', 'ready', []], 'rand' => ['apps', 'ready', []],
        'pw' => ['apps', 'ready', []], 'ball' => ['apps', 'ready', []], 'joke' => ['apps', 'ready', []],
        'fact' => ['apps', 'ready', []], 'tip' => ['apps', 'ready', []],
        // RSS feeds and watchers
        'rss' => ['rss', 'ready', ['rssmine']], 'rssmix' => ['rss', 'ready', ['rssmine']], 'rsskey' => ['rss', 'ready', ['rssmine']],
        'rsswater' => ['rss', 'ready', ['rss:water']], 'rsspower' => ['rss', 'ready', ['rss:power']],
        'rssphilstar' => ['rss', 'ready', ['rss:philstar']], 'rssrappler' => ['rss', 'ready', ['rss:rappler']],
        'rssgma' => ['rss', 'ready', ['rss:gma']], 'rssgdacs' => ['rss', 'ready', ['rss:gdacs']], 'rsswho' => ['rss', 'ready', ['rss:who']],
        'rssusgs' => ['rss', 'ready', ['rss:usgs']], 'rsspna' => ['rss', 'ready', ['rss:pna', 'rss:inquirer', 'rss:doh']],
        // just for me
        'todo' => ['me', 'ready', ['prefs']], 'sticky' => ['me', 'ready', ['prefs']], 'count' => ['me', 'ready', ['prefs']],
        'water' => ['me', 'ready', ['prefs', 'wx']], 'mood' => ['me', 'new', ['mood']], 'goal' => ['me', 'ready', ['prefs', 'mine']],
        'mantra' => ['me', 'ready', []], 'habit' => ['me', 'ready', ['prefs']], 'shiftn' => ['me', 'ready', ['prefs']],
    ];
    foreach (WS_GAMES as $g) {
        $c[$g] = ['games', 'ready', ['games']];
    }
    return $c;
}

/** The groups a set of widget ids needs, plus any asked for by name (alarm, prefs, settings, meta). */
function widget_groups_for(array $ids, array $extra = []): array
{
    $cat = widget_catalogue();
    $named = ['alarm', 'prefs', 'settings', 'meta', 'mine'];
    $out = [];
    foreach ($ids as $id) {
        foreach ($cat[$id][2] ?? [] as $g) { $out[$g] = true; }
    }
    foreach ($extra as $g) {
        if (in_array($g, $named, true)) { $out[$g] = true; }
    }
    return array_keys($out);
}

// ---------------------------------------------------------------------------------------------------------------------
// outside sources
// ---------------------------------------------------------------------------------------------------------------------

/** NOAA's heat index (the one PAGASA reports), from °C and relative humidity, in °C. */
function ws_heat_index(float $tc, float $rh): float
{
    $t  = $tc * 9 / 5 + 32;
    $hi = 0.5 * ($t + 61.0 + (($t - 68.0) * 1.2) + ($rh * 0.094));
    if (($hi + $t) / 2 >= 80) {
        $hi = -42.379 + 2.04901523 * $t + 10.14333127 * $rh - 0.22475541 * $t * $rh - 0.00683783 * $t * $t
            - 0.05481717 * $rh * $rh + 0.00122874 * $t * $t * $rh + 0.00085282 * $t * $rh * $rh - 0.00000199 * $t * $t * $rh * $rh;
        if ($rh < 13 && $t >= 80 && $t <= 112) {
            $hi -= ((13 - $rh) / 4) * sqrt((17 - abs($t - 95)) / 17);
        } elseif ($rh > 85 && $t >= 80 && $t <= 87) {
            $hi += (($rh - 85) / 10) * ((87 - $t) / 5);
        }
    }
    return ($hi - 32) * 5 / 9;
}

/** PAGASA's heat index classification: 27-32 caution, 33-41 extreme caution, 42-51 danger, 52 and up extreme danger. */
function ws_heat_band(float $c): ?string
{
    $c = round($c);
    return $c >= 52 ? 'extreme_danger' : ($c >= 42 ? 'danger' : ($c >= 33 ? 'extreme_caution' : ($c >= 27 ? 'caution' : null)));
}

/** The moon's phase (0 new, 0.5 full), lit fraction and name key, from the mean synodic month. */
function ws_moon(int $ts): array
{
    $ref = 947182440;                       // a new moon: 2000-01-06 18:14 UTC
    $syn = 29.530588853 * 86400;
    $p = fmod(($ts - $ref) / $syn, 1.0);
    if ($p < 0) { $p += 1; }
    $names = [[0.0339, 'new'], [0.216, 'waxing_crescent'], [0.284, 'first_quarter'], [0.466, 'waxing_gibbous'], [0.534, 'full'],
              [0.716, 'waning_gibbous'], [0.784, 'last_quarter'], [0.9661, 'waning_crescent'], [1.01, 'new']];
    $name = 'new';
    foreach ($names as [$lim, $n]) { if ($p < $lim) { $name = $n; break; } }
    return ['phase' => round($p, 3), 'lit' => (int) round(100 * (1 - cos(2 * M_PI * $p)) / 2), 'name' => $name,
            'age_days' => round($p * 29.530588853, 1)];
}

function ws_wx(): array
{
    $url = 'https://api.open-meteo.com/v1/forecast?' . http_build_query([
        'latitude' => HZ_LAT, 'longitude' => HZ_LNG, 'timezone' => 'Asia/Manila', 'forecast_days' => 7,
        'current' => 'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,pressure_msl,uv_index,is_day',
        'hourly'  => 'temperature_2m,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,uv_index',
        'daily'   => 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset,uv_index_max,wind_gusts_10m_max',
    ]);
    $r = feed_cached('wx-v1', 600, static function () use ($url): ?array {
        $j = feed_json($url);
        return isset($j['current'], $j['hourly']['time'], $j['daily']['time']) ? $j : null;
    });
    if (!$r['ok']) {
        return $r;
    }
    $j = $r['data'];
    $tz = new DateTimeZone('Asia/Manila');
    $now = new DateTimeImmutable('now', $tz);
    $c = $j['current'];
    $h = $j['hourly'];
    $hours = [];
    $start = null;
    foreach ($h['time'] as $i => $t) {
        if ($start === null && $t >= $now->format('Y-m-d\TH:00')) { $start = $i; }
    }
    $start ??= 0;
    for ($i = $start; $i < min(count($h['time']), $start + 24); $i++) {
        $hi = ws_heat_index((float) $h['temperature_2m'][$i], (float) $h['relative_humidity_2m'][$i]);
        $hours[] = ['t' => $h['time'][$i], 'temp' => $h['temperature_2m'][$i], 'pop' => $h['precipitation_probability'][$i],
                    'rain' => $h['precipitation'][$i], 'code' => $h['weather_code'][$i], 'wind' => $h['wind_speed_10m'][$i],
                    'gust' => $h['wind_gusts_10m'][$i], 'dir' => $h['wind_direction_10m'][$i], 'pressure' => $h['pressure_msl'][$i],
                    'uv' => $h['uv_index'][$i], 'heat' => (int) round($hi)];
    }
    // the hottest heat index left today
    $peak = null;
    foreach ($h['time'] as $i => $t) {
        if (substr($t, 0, 10) !== $now->format('Y-m-d') || $i < $start) continue;
        $hi = ws_heat_index((float) $h['temperature_2m'][$i], (float) $h['relative_humidity_2m'][$i]);
        if ($peak === null || $hi > $peak['c']) { $peak = ['c' => (int) round($hi), 'at' => $t, 'band' => ws_heat_band($hi)]; }
    }
    // pressure three hours ago against now: a fall of 3 hPa or more in three hours is a storm sign
    $trend = null;
    if ($start >= 3) {
        $trend = round((float) $h['pressure_msl'][$start] - (float) $h['pressure_msl'][$start - 3], 1);
    }
    $d = $j['daily'];
    $days = [];
    foreach ($d['time'] as $i => $t) {
        $days[] = ['d' => $t, 'code' => $d['weather_code'][$i], 'max' => $d['temperature_2m_max'][$i], 'min' => $d['temperature_2m_min'][$i],
                   'rain' => $d['precipitation_sum'][$i], 'pop' => $d['precipitation_probability_max'][$i], 'sunrise' => $d['sunrise'][$i],
                   'sunset' => $d['sunset'][$i], 'uv' => $d['uv_index_max'][$i], 'gust' => $d['wind_gusts_10m_max'][$i]];
    }
    $heatNow = ws_heat_index((float) $c['temperature_2m'], (float) $c['relative_humidity_2m']);
    $sunset = isset($days[0]['sunset']) ? new DateTimeImmutable($days[0]['sunset'], $tz) : null;
    $r['data'] = [
        'now' => ['temp' => $c['temperature_2m'], 'feels' => $c['apparent_temperature'], 'humidity' => $c['relative_humidity_2m'],
                  'rain' => $c['precipitation'], 'code' => $c['weather_code'], 'wind' => $c['wind_speed_10m'], 'dir' => $c['wind_direction_10m'],
                  'gust' => $c['wind_gusts_10m'], 'pressure' => $c['pressure_msl'], 'uv' => $c['uv_index'], 'day' => (bool) $c['is_day'],
                  'at' => $c['time']],
        'heat' => ['c' => (int) round($heatNow), 'band' => ws_heat_band($heatNow), 'peak' => $peak],
        'pressure_3h' => $trend,
        'hours' => $hours,
        'days' => $days,
        'moon' => ws_moon(time()),
        'daylight_left_min' => $sunset && $sunset > $now ? (int) round(($sunset->getTimestamp() - $now->getTimestamp()) / 60) : 0,
        'source' => 'Open-Meteo',
    ];
    return $r;
}

function ws_air(): array
{
    $url = 'https://air-quality-api.open-meteo.com/v1/air-quality?' . http_build_query([
        'latitude' => HZ_LAT, 'longitude' => HZ_LNG, 'timezone' => 'Asia/Manila',
        'current' => 'us_aqi,pm2_5,pm10,nitrogen_dioxide,ozone,carbon_monoxide',
    ]);
    $r = feed_cached('air-v1', 1800, static function () use ($url): ?array {
        $j = feed_json($url);
        return isset($j['current']['us_aqi']) ? $j['current'] : null;
    });
    if ($r['ok']) {
        $a = (int) $r['data']['us_aqi'];
        $r['data']['band'] = $a <= 50 ? 'good' : ($a <= 100 ? 'moderate' : ($a <= 150 ? 'sensitive' : ($a <= 200 ? 'unhealthy' : ($a <= 300 ? 'very_unhealthy' : 'hazardous'))));
        $r['data']['source'] = 'Open-Meteo (CAMS)';
    }
    return $r;
}

/** Manila Bay off Pasay: sea level (a global tide model, not an official tide table) and waves. */
function ws_marine(): array
{
    $url = 'https://marine-api.open-meteo.com/v1/marine?' . http_build_query([
        'latitude' => 14.53, 'longitude' => 120.96, 'timezone' => 'Asia/Manila', 'forecast_days' => 3,
        'hourly' => 'sea_level_height_msl,wave_height,swell_wave_height,swell_wave_period,wave_direction',
    ]);
    $r = feed_cached('marine-v1', 1800, static function () use ($url): ?array {
        $j = feed_json($url);
        return isset($j['hourly']['time']) ? $j['hourly'] : null;
    });
    if (!$r['ok']) {
        return $r;
    }
    $h = $r['data'];
    $now = (new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d\TH:00');
    $i0 = 0;
    foreach ($h['time'] as $i => $t) { if ($t <= $now) { $i0 = $i; } }
    $lv = $h['sea_level_height_msl'];
    $turns = [];
    for ($i = max(1, $i0); $i < min(count($lv) - 1, $i0 + 36); $i++) {
        if ($lv[$i] === null || $lv[$i - 1] === null || $lv[$i + 1] === null) continue;
        if ($lv[$i] > $lv[$i - 1] && $lv[$i] >= $lv[$i + 1]) { $turns[] = ['kind' => 'high', 't' => $h['time'][$i], 'm' => $lv[$i]]; }
        if ($lv[$i] < $lv[$i - 1] && $lv[$i] <= $lv[$i + 1]) { $turns[] = ['kind' => 'low', 't' => $h['time'][$i], 'm' => $lv[$i]]; }
    }
    $curve = [];
    for ($i = $i0; $i < min(count($lv), $i0 + 24); $i++) { $curve[] = ['t' => $h['time'][$i], 'm' => $lv[$i]]; }
    return ['ok' => true, 'stale' => $r['stale'], 'at' => $r['at'], 'data' => [
        'level' => $lv[$i0] ?? null,
        'rising' => isset($lv[$i0 + 1], $lv[$i0]) ? $lv[$i0 + 1] > $lv[$i0] : null,
        'turns' => array_slice($turns, 0, 4),
        'curve' => $curve,
        'waves' => ['height' => $h['wave_height'][$i0] ?? null, 'swell' => $h['swell_wave_height'][$i0] ?? null,
                    'period' => $h['swell_wave_period'][$i0] ?? null, 'dir' => $h['wave_direction'][$i0] ?? null],
        'model' => true,
        'source' => 'Open-Meteo Marine',
    ]];
}

/** Quakes of magnitude 3 and up in and around the Philippines in the last week (USGS; PHIVOLCS has no public feed). */
function ws_quake(): array
{
    return feed_cached('quake-v1', 600, static function (): ?array {
        $url = 'https://earthquake.usgs.gov/fdsnws/event/1/query?' . http_build_query([
            'format' => 'geojson', 'starttime' => gmdate('Y-m-d\TH:i:s', time() - 7 * 86400), 'minmagnitude' => 3,
            'minlatitude' => 4, 'maxlatitude' => 21.5, 'minlongitude' => 116, 'maxlongitude' => 127, 'orderby' => 'time', 'limit' => 30,
        ]);
        $j = feed_json($url, 10);
        if (!isset($j['features'])) {
            return null;
        }
        $out = [];
        foreach ($j['features'] as $f) {
            $p = $f['properties'] ?? []; $g = $f['geometry']['coordinates'] ?? [null, null, null];
            if ($g[0] === null) continue;
            $out[] = ['mag' => round((float) $p['mag'], 1), 'place' => (string) ($p['place'] ?? ''), 'at' => gmdate('c', (int) (($p['time'] ?? 0) / 1000)),
                      'depth_km' => round((float) $g[2]), 'km' => (int) round(hz_km(HZ_LAT, HZ_LNG, (float) $g[1], (float) $g[0])),
                      'dir' => hz_dir(HZ_LAT, HZ_LNG, (float) $g[1], (float) $g[0]), 'lat' => (float) $g[1], 'lng' => (float) $g[0],
                      'url' => preg_match('#^https://earthquake\.usgs\.gov/#', (string) ($p['url'] ?? '')) ? (string) $p['url'] : ''];
        }
        return ['quakes' => $out, 'source' => 'USGS'];
    });
}

/** Philippine public holidays this year and next (Nager.Date). */
function ws_holidays(): array
{
    $r = feed_cached('holidays-v1-' . date('Y'), 86400, static function (): ?array {
        $all = [];
        foreach ([(int) date('Y'), (int) date('Y') + 1] as $y) {
            $j = feed_json('https://date.nager.at/api/v3/PublicHolidays/' . $y . '/PH');
            if (!is_array($j)) return null;
            foreach ($j as $h) {
                $all[] = ['date' => (string) $h['date'], 'name' => (string) ($h['name'] ?? ''), 'local' => (string) ($h['localName'] ?? '')];
            }
        }
        return $all;
    });
    if ($r['ok']) {
        $today = (new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('Y-m-d');
        $r['data'] = ['next' => array_values(array_slice(array_filter($r['data'], static fn ($h) => $h['date'] >= $today), 0, 12)),
                      'source' => 'Nager.Date'];
    }
    return $r;
}

/** Evacuation centres and halls near the barangay hall, nearest first, with what the lead wrote about each. */
function ws_evac(Supabase $db): array
{
    // The public Overpass servers took 35 to 42 seconds on 17 Oct 2026, past what a page can wait: the safe points around
    // the hall are kept in a file built by tools/build_safe.php (as transit is), and a live answer is only the fallback.
    $file = __DIR__ . '/../assets/data/safe-b183.json';
    $fc = is_file($file) ? json_decode((string) file_get_contents($file), true) : null;
    if (!is_array($fc) || !isset($fc['features'])) {
        $box = [round(HZ_LNG - 0.015, 3), round(HZ_LAT - 0.015, 3), round(HZ_LNG + 0.015, 3), round(HZ_LAT + 0.015, 3)];
        $fc = osm_layer('safe', $box);
    }
    if ($fc === null) {
        return ['ok' => false, 'stale' => false, 'at' => null, 'data' => null];
    }
    $notes = [];
    try {
        foreach ($db->select('safe_point_notes', ['select' => 'osm_id,name,capacity,status,note,updated_at']) as $n) {
            $notes[$n['osm_id']] = $n;
        }
    } catch (SupabaseError) { /* the points still show, without notes */ }
    // distances from the Barangay 183 hall itself where the map has it (it sits about 600 m from the barangay's centre)
    [$oLat, $oLng] = [HZ_LAT, HZ_LNG];
    foreach ($fc['features'] as $f) {
        if (($f['properties']['k'] ?? '') === 'hall' && preg_match('/\b183\b/', (string) ($f['properties']['name'] ?? ''))) {
            [$oLng, $oLat] = $f['geometry']['coordinates'];
            break;
        }
    }
    $out = [];
    foreach ($fc['features'] as $f) {
        $p = $f['properties'] ?? [];
        if (!in_array($p['k'] ?? '', ['evac', 'hall'], true)) continue;
        [$lng, $lat] = $f['geometry']['coordinates'];
        $id = (string) ($p['id'] ?? '');
        $n = $notes[$id] ?? null;
        $name = (string) ($n['name'] ?? '') ?: (string) ($p['name'] ?? '');
        if ($name === '') continue;   // an unnamed shelter is usually a waiting shed: no one can be sent to it
        $out[] = ['id' => $id, 'name' => $name, 'kind' => (string) ($p['sub'] ?? $p['k']),
                  'lat' => $lat, 'lng' => $lng, 'm' => (int) round(hz_km((float) $oLat, (float) $oLng, (float) $lat, (float) $lng) * 1000),
                  'capacity' => $n['capacity'] ?? (is_numeric($p['cap'] ?? '') ? (int) $p['cap'] : null),
                  'status' => $n['status'] ?? 'unknown', 'note' => $n['note'] ?? null, 'addr' => (string) ($p['addr'] ?? '')];
    }
    usort($out, static fn ($a, $b) => $a['m'] <=> $b['m']);
    return ['ok' => true, 'stale' => false, 'at' => $fc['built'] ?? gmdate('c'),
            'data' => ['points' => array_slice($out, 0, 15), 'from' => ['lat' => $oLat, 'lng' => $oLng], 'source' => 'OpenStreetMap']];
}

// ---------------------------------------------------------------------------------------------------------------------
// the answer
// ---------------------------------------------------------------------------------------------------------------------

/**
 * Builds every group asked for. Each group is {ok, stale, at, data}; a failed group is ok=false with data null and
 * never takes another group down with it.
 *
 * @param list<string> $groups
 * @return array<string, array{ok:bool, stale:bool, at:?string, data:mixed}>
 */
function widget_data(Supabase $db, array $admin, array $groups): array
{
    $tz    = new DateTimeZone('Asia/Manila');
    $now   = new DateTimeImmutable('now', $tz);
    $today = $now->setTime(0, 0);
    $iso   = static fn (DateTimeImmutable $d): string => $d->format('Y-m-d\TH:i:sP');
    $me    = (string) $admin['id'];
    $want  = array_flip($groups);
    $out   = [];
    $fail  = static fn (): array => ['ok' => false, 'stale' => false, 'at' => null, 'data' => null];
    $good  = static fn ($d): array => ['ok' => true, 'stale' => false, 'at' => gmdate('c'), 'data' => $d];

    // ---- the database, in one parallel batch
    $q = [];
    if (isset($want['brief']))       { $q['summary'] = ['rpc/smart_summary', [], true]; $q['riskdl'] = ['rpc/smart_deadline_risk', [], true]; }
    if (isset($want['numbers']))     { $q['numbers'] = ['rpc/workspace_numbers', [], true]; }
    if (isset($want['team']))        { $q['team'] = ['rpc/workspace_team', [], true]; }
    if (isset($want['risk']))        { $q['risk'] = ['rpc/workspace_risk', [], true]; }
    if (isset($want['queue']))       { $q['queue'] = ['rpc/smart_queue', ['p_limit' => 60], true]; }
    if (isset($want['recur']))       { $q['recur'] = ['rpc/smart_patterns', ['p_days' => null], true]; }
    if (isset($want['sla']))         { $q['sla'] = ['rpc/smart_sla_scorecard', [], true]; }
    if (isset($want['activity']))    { $q['activity'] = ['rpc/workspace_activity', ['p_limit' => 12], true]; }
    if (isset($want['photos']))      { $q['photos'] = ['rpc/workspace_photos', ['p_limit' => 8], true]; }
    if (isset($want['alarm']))       { $q['alarm'] = ['rpc/workspace_alarm_db', [], true]; }
    if (isset($want['due'])) {
        $q['due'] = ['reports', ['select' => 'id,tracking_id,subject,due_at,is_sensitive,status,handler:users!reports_handler_id_fkey(full_name)',
                                 'deleted_at' => 'is.null', 'status' => WS_OPEN, 'due_at' => 'lt.' . $iso($today->modify('+8 days')),
                                 'order' => 'due_at.asc', 'limit' => '40'], true];
    }
    if (isset($want['map'])) {
        $q['map'] = ['reports', ['select' => 'id,tracking_id,category,latitude,longitude,is_sensitive,status,report_triage(effective_level)',
                                 'deleted_at' => 'is.null', 'status' => WS_OPEN, 'order' => 'created_at.desc', 'limit' => '500'], true];
    }
    if (isset($want['hotlines'])) {
        $q['hotlines'] = ['hotline_groups', ['select' => 'id,name,icon,sort_order,parent_id,hotline_numbers(label,number,carrier,sort_order,is_active)',
                                             'is_active' => 'is.true', 'order' => 'sort_order.asc'], true];
    }
    if (isset($want['posts'])) {
        $q['posts'] = ['team_posts', ['select' => 'id,kind,body,author_id,pinned_until,created_at,author:users!team_posts_author_id_fkey(full_name,official_role),team_post_reads(user_id)',
                                      'removed_at' => 'is.null', 'created_at' => 'gte.' . $iso($today->modify('-30 days')),
                                      'order' => 'created_at.desc', 'limit' => '60'], true];
        $q['staff_n'] = ['users', ['select' => 'id', 'role' => 'eq.admin', 'removed_at' => 'is.null', 'is_suspended' => 'is.false'], true];
    }
    if (isset($want['polls'])) {
        $q['polls'] = ['polls', ['select' => 'id,question,options,created_by,closes_at,closed_at,created_at,author:users!polls_created_by_fkey(full_name),poll_votes(user_id,choice)',
                                 'or' => '(closed_at.is.null,closed_at.gte.' . $iso($today->modify('-7 days')) . ')',
                                 'order' => 'created_at.desc', 'limit' => '10'], true];
    }
    if (isset($want['checkpoints'])) {
        $q['cps'] = ['patrol_checkpoints', ['select' => 'id,name,lat,lng,sort_order', 'is_active' => 'is.true', 'order' => 'sort_order.asc,name.asc'], true];
        $q['scans'] = ['checkpoint_scans', ['select' => 'id,checkpoint_id,tanod_id,scanned_at,tanod:users!checkpoint_scans_tanod_id_fkey(full_name)',
                                            'scanned_at' => 'gte.' . $iso($today), 'order' => 'scanned_at.desc', 'limit' => '200'], true];
    }
    if (isset($want['relief'])) {
        $q['relief'] = ['relief_tally', ['select' => 'id,event,street,packs,given_on,recorded_by',
                                         'given_on' => 'gte.' . $today->modify('-60 days')->format('Y-m-d'), 'order' => 'given_on.desc', 'limit' => '500'], true];
    }
    if (isset($want['mood'])) {
        $q['mood_me'] = ['shift_checkins', ['select' => 'mood,shift_date', 'shift_date' => 'eq.' . $today->format('Y-m-d')], true];
        $q['mood_all'] = ['rpc/shift_mood_totals', [], true];
    }
    if (isset($want['settings']) || isset($want['games']) || isset($want['alarm']) || isset($want['posts'])) {
        $q['settings'] = ['workspace_settings', ['select' => 'alarm_rules,games_enabled,shift_starts,fares,updated_at', 'id' => 'eq.1'], true];
        $q['lead'] = ['rpc/_ws_is_lead', [], true];
    }
    if (isset($want['prefs'])) {
        $q['prefs'] = ['workspace_prefs', ['select' => 'tabs,tab,feeds,keywords,mine,updated_at', 'user_id' => 'eq.' . $me], true];
    }
    if (isset($want['games'])) {
        $q['scores'] = ['game_scores', ['select' => 'user_id,game,best,plays,updated_at,user:users!game_scores_user_id_fkey(full_name)', 'limit' => '1000'], true];
    }
    if (isset($want['rssmine']) && !isset($q['prefs'])) {
        $q['prefs'] = ['workspace_prefs', ['select' => 'tabs,tab,feeds,keywords,mine,updated_at', 'user_id' => 'eq.' . $me], true];
    }

    $got = [];
    if ($q) {
        try {
            $got = $db->selectMany($q);
        } catch (SupabaseError) {
            $got = [];
        }
    }
    $has = static fn (string $k): bool => isset($got[$k]) && !($got[$k] instanceof SupabaseError);
    $rows = static fn (string $k): array => (isset($got[$k]) && !($got[$k] instanceof SupabaseError) && is_array($got[$k])) ? $got[$k] : [];

    $counts = [];
    if (isset($want['brief']) || isset($want['mine'])) {
        $week0 = $today->modify('monday this week');
        $cq = [];
        if (isset($want['brief'])) {
            $cq += [
                'open'      => ['reports', ['deleted_at' => 'is.null', 'status' => WS_OPEN], true],
                'overdue'   => ['reports', ['deleted_at' => 'is.null', 'status' => WS_OPEN, 'due_at' => 'lt.' . $iso($now)], true],
                'due_today' => ['reports', ['deleted_at' => 'is.null', 'status' => WS_OPEN, 'and' => '(due_at.gte.' . $iso($today) . ',due_at.lt.' . $iso($today->modify('+1 day')) . ')'], true],
                'in_today'  => ['reports', ['deleted_at' => 'is.null', 'created_at' => 'gte.' . $iso($today)], true],
                'out_today' => ['reports', ['deleted_at' => 'is.null', 'resolved_at' => 'gte.' . $iso($today)], true],
            ];
        }
        if (isset($want['mine'])) {
            $cq += [
                'mine_closed' => ['reports', ['deleted_at' => 'is.null', 'handler_id' => 'eq.' . $me, 'resolved_at' => 'gte.' . $iso($week0)], true],
                'mine_open'   => ['reports', ['deleted_at' => 'is.null', 'handler_id' => 'eq.' . $me, 'status' => WS_OPEN], true],
            ];
        }
        try {
            foreach ($db->selectMany($cq, true) as $k => $v) { $counts[$k] = is_int($v) ? $v : null; }
        } catch (SupabaseError) { /* counts stay empty */ }
    }

    $settings = $rows('settings')[0] ?? null;
    $isLead = $has('lead') && $got['lead'] === true;

    foreach ($groups as $g) {
        switch (true) {
            case $g === 'brief':
                $sum = $has('summary') && is_array($got['summary']) ? $got['summary'] : null;
                if ($sum === null && !$counts) { $out[$g] = $fail(); break; }
                $hour = (int) $now->format('G');
                $out[$g] = $good([
                    'period' => $hour < 12 ? 'morning' : ($hour < 18 ? 'afternoon' : 'night'),
                    'urgent_waiting' => (int) ($sum['urgent_waiting'] ?? 0), 'high_waiting' => (int) ($sum['high_waiting'] ?? 0),
                    'recurring_open' => (int) ($sum['recurring_open'] ?? 0),
                    'open' => $counts['open'] ?? null, 'overdue' => $counts['overdue'] ?? null, 'due_today' => $counts['due_today'] ?? null,
                    'in_today' => $counts['in_today'] ?? null, 'out_today' => $counts['out_today'] ?? null,
                    'may_miss' => count(array_filter($rows('riskdl'), static fn ($r) => ($r['risk'] ?? '') === 'high')),
                ]);
                break;
            case in_array($g, ['numbers', 'team', 'risk', 'recur', 'sla', 'activity', 'photos'], true):
                $out[$g] = $has($g) ? $good($got[$g]) : $fail();
                break;
            case $g === 'queue':
                $out[$g] = $has('queue') ? $good(array_values(array_slice(array_filter($rows('queue'),
                    static fn ($r) => in_array($r['stage'] ?? '', ['review', 'dispatch'], true)), 0, 10))) : $fail();
                break;
            case $g === 'due':
                if (!$has('due')) { $out[$g] = $fail(); break; }
                $list = array_map(static fn ($r) => ['report_id' => $r['id'], 'tracking_id' => $r['tracking_id'], 'subject' => $r['subject'],
                    'sensitive' => (bool) $r['is_sensitive'], 'due_at' => $r['due_at'], 'handler' => $r['handler']['full_name'] ?? null,
                    'overdue' => $r['due_at'] !== null && strtotime($r['due_at']) < time()], $rows('due'));
                $out[$g] = $good($list);
                break;
            case $g === 'map':
                if (!$has('map')) { $out[$g] = $fail(); break; }
                $out[$g] = $good(array_map(static fn ($r) => ['report_id' => $r['id'], 'tracking_id' => $r['tracking_id'], 'category' => $r['category'],
                    'lat' => $r['latitude'], 'lng' => $r['longitude'], 'sensitive' => (bool) $r['is_sensitive'], 'status' => $r['status'],
                    'level' => $r['report_triage']['effective_level'] ?? ($r['report_triage'][0]['effective_level'] ?? null)], $rows('map')));
                break;
            case $g === 'hotlines':
                if (!$has('hotlines')) { $out[$g] = $fail(); break; }
                $list = [];
                foreach ($rows('hotlines') as $hg) {
                    $nums = array_values(array_filter((array) ($hg['hotline_numbers'] ?? []), static fn ($n) => !empty($n['is_active'])));
                    usort($nums, static fn ($a, $b) => ($a['sort_order'] ?? 0) <=> ($b['sort_order'] ?? 0));
                    $list[] = ['name' => $hg['name'], 'icon' => $hg['icon'], 'parent' => $hg['parent_id'],
                               'numbers' => array_map(static fn ($n) => ['label' => $n['label'], 'number' => $n['number'], 'carrier' => $n['carrier']], $nums)];
                }
                $out[$g] = $good($list);
                break;
            case $g === 'posts':
                if (!$has('posts')) { $out[$g] = $fail(); break; }
                $staff = count($rows('staff_n'));
                $list = [];
                foreach ($rows('posts') as $p) {
                    $pinned = $p['pinned_until'] !== null && strtotime($p['pinned_until']) > time();
                    if ($p['kind'] === 'notice' && !$pinned && strtotime($p['created_at']) < time() - 3 * 86400) continue;
                    $readers = array_column((array) ($p['team_post_reads'] ?? []), 'user_id');
                    $list[] = ['id' => $p['id'], 'kind' => $p['kind'], 'body' => $p['body'], 'at' => $p['created_at'], 'pinned' => $pinned,
                               'pinned_until' => $p['pinned_until'], 'author' => $p['author']['full_name'] ?? null,
                               'author_position' => $p['author']['official_role'] ?? null, 'mine' => $p['author_id'] === $me,
                               'seen' => count($readers), 'seen_by_me' => in_array($me, $readers, true)];
                }
                $out[$g] = $good(['posts' => $list, 'staff' => $staff, 'can_notice' => $isLead]);
                break;
            case $g === 'polls':
                if (!$has('polls')) { $out[$g] = $fail(); break; }
                $list = [];
                foreach ($rows('polls') as $p) {
                    $tally = array_fill(0, count($p['options']), 0);
                    $mine = null;
                    foreach ((array) ($p['poll_votes'] ?? []) as $v) {
                        $tally[(int) $v['choice']] = ($tally[(int) $v['choice']] ?? 0) + 1;
                        if ($v['user_id'] === $me) { $mine = (int) $v['choice']; }
                    }
                    $open = $p['closed_at'] === null && ($p['closes_at'] === null || strtotime($p['closes_at']) > time());
                    $list[] = ['id' => $p['id'], 'question' => $p['question'], 'options' => $p['options'], 'votes' => $tally, 'my_vote' => $mine,
                               'open' => $open, 'closes_at' => $p['closes_at'], 'author' => $p['author']['full_name'] ?? null,
                               'mine' => $p['created_by'] === $me, 'at' => $p['created_at']];
                }
                $out[$g] = $good($list);
                break;
            case $g === 'checkpoints':
                if (!$has('cps')) { $out[$g] = $fail(); break; }
                $last = [];
                foreach ($rows('scans') as $s) {
                    $last[$s['checkpoint_id']] ??= ['at' => $s['scanned_at'], 'tanod' => $s['tanod']['full_name'] ?? null];
                }
                $out[$g] = $good(array_map(static fn ($c) => ['id' => $c['id'], 'name' => $c['name'], 'lat' => $c['lat'], 'lng' => $c['lng'],
                    'today' => $last[$c['id']] ?? null], $rows('cps')));
                break;
            case $g === 'relief':
                if (!$has('relief')) { $out[$g] = $fail(); break; }
                $by = [];
                foreach ($rows('relief') as $r) {
                    $by[$r['event']]['total'] = ($by[$r['event']]['total'] ?? 0) + (int) $r['packs'];
                    $by[$r['event']]['streets'][$r['street']] = ($by[$r['event']]['streets'][$r['street']] ?? 0) + (int) $r['packs'];
                    $by[$r['event']]['last'] = max($by[$r['event']]['last'] ?? '', (string) $r['given_on']);
                }
                $events = [];
                foreach ($by as $ev => $v) {
                    arsort($v['streets']);
                    $events[] = ['event' => $ev, 'total' => $v['total'], 'last' => $v['last'],
                                 'streets' => array_map(static fn ($s, $n) => ['street' => $s, 'packs' => $n], array_keys($v['streets']), $v['streets'])];
                }
                usort($events, static fn ($a, $b) => strcmp($b['last'], $a['last']));
                $out[$g] = $good(['events' => $events, 'lines' => array_slice($rows('relief'), 0, 30)]);
                break;
            case $g === 'mood':
                $out[$g] = $has('mood_me') ? $good(['mine' => $rows('mood_me')[0]['mood'] ?? null,
                    'totals' => $has('mood_all') ? $got['mood_all'] : null]) : $fail();
                break;
            case $g === 'settings':
                $out[$g] = $settings ? $good($settings + ['is_lead' => $isLead]) : $fail();
                break;
            case $g === 'prefs':
                if (!$has('prefs')) { $out[$g] = $fail(); break; }
                $out[$g] = $good($rows('prefs')[0] ?? ['tabs' => WS_DEFAULT_TABS, 'tab' => null,
                    'feeds' => [], 'keywords' => [], 'mine' => new stdClass(), 'updated_at' => null]);
                break;
            case $g === 'mine':
                $out[$g] = $counts ? $good(['closed_this_week' => $counts['mine_closed'] ?? null, 'open' => $counts['mine_open'] ?? null]) : $fail();
                break;
            case $g === 'games':
                if (!$settings) { $out[$g] = $fail(); break; }
                $board = [];
                foreach ($rows('scores') as $s) {
                    $board[$s['game']][] = ['user_id' => $s['user_id'], 'name' => $s['user']['full_name'] ?? null, 'best' => (float) $s['best'], 'plays' => (int) $s['plays']];
                }
                $low = ['mem', 'react', 'whack', 'wordl', 'sudoku', 'mines'];
                foreach ($board as $game => &$list) {
                    usort($list, static fn ($a, $b) => in_array($game, $low, true) ? $a['best'] <=> $b['best'] : $b['best'] <=> $a['best']);
                    $list = array_slice($list, 0, 5);
                }
                unset($list);
                $mineBest = [];
                foreach ($rows('scores') as $s) { if ($s['user_id'] === $me) { $mineBest[$s['game']] = (float) $s['best']; } }
                $out[$g] = $good(['enabled' => (bool) $settings['games_enabled'], 'lower_is_better' => $low, 'top' => $board, 'mine' => $mineBest]);
                break;
            case $g === 'alarm':
                $db_ = $has('alarm') ? $got['alarm'] : null;
                $rules = (array) ($settings['alarm_rules'] ?? ($db_['rules'] ?? []));
                $hz = in_array('red', $rules, true) || in_array('sig3', $rules, true) ? hazards_read() : null;
                $firing = [];
                if (in_array('red', $rules, true) && $hz) {
                    foreach ($hz['warnings'] as $w) {
                        if ((int) $w['level'] >= 3 && !empty($w['metro'])) { $firing[] = ['rule' => 'red', 'tab' => 'flood', 'detail' => $w['type'] . ' · ' . $w['region']]; break; }
                    }
                }
                if (in_array('sig3', $rules, true) && $hz && ($hz['cyclone']['signal'] ?? 0) >= 3) {
                    $firing[] = ['rule' => 'sig3', 'tab' => 'ty', 'detail' => 'Signal ' . $hz['cyclone']['signal'] . ' · ' . ($hz['cyclone']['name'] ?? '')];
                }
                if (in_array('urgent2h', $rules, true) && !empty($db_['urgent2h'])) {
                    $firing[] = ['rule' => 'urgent2h', 'tab' => 'queue', 'detail' => count($db_['urgent2h']) . ' · ' . ($db_['urgent2h'][0]['tracking_id'] ?? ''),
                                 'cases' => $db_['urgent2h']];
                }
                if (in_array('deadline', $rules, true) && !empty($db_['deadline'])) {
                    $firing[] = ['rule' => 'deadline', 'tab' => 'due', 'detail' => count($db_['deadline']) . ' · ' . ($db_['deadline'][0]['tracking_id'] ?? ''),
                                 'cases' => $db_['deadline']];
                }
                $out[$g] = ($db_ === null && !$settings) ? $fail()
                    : $good(['rules' => $rules, 'firing' => $firing, 'hazards_stale' => $hz['stale'] ?? null, 'hazards_ok' => $hz['ok'] ?? null]);
                break;
            case $g === 'meta':
                $out[$g] = $good(['hall' => ['lat' => HZ_LAT, 'lng' => HZ_LNG, 'phone' => env('BARANGAY_HALL_PHONE', ''), 'hours' => env('BARANGAY_HALL_HOURS', '')],
                                  'app_url' => preg_match('#^https://#', (string) env('RESIDENT_APP_URL', '')) ? env('RESIDENT_APP_URL', '') : '',
                                  'now' => $now->format(DATE_ATOM), 'tz' => 'Asia/Manila']);
                break;
            case $g === 'hazards':
                $h = hazards_read();
                $out[$g] = ['ok' => (bool) $h['ok'], 'stale' => (bool) ($h['stale'] ?? false), 'at' => $h['at'] ?? null, 'data' => $h];
                break;
            case $g === 'wx':       $out[$g] = ws_wx(); break;
            case $g === 'air':      $out[$g] = ws_air(); break;
            case $g === 'marine':   $out[$g] = ws_marine(); break;
            case $g === 'quake':    $out[$g] = ws_quake(); break;
            case $g === 'holidays': $out[$g] = ws_holidays(); break;
            case $g === 'evac':     $out[$g] = ws_evac($db); break;
            case str_starts_with($g, 'rss:'):
                $key = substr($g, 4);
                $r = feed_read_named($key);
                $cat = feed_catalogue();
                if ($r['ok']) {
                    $r['data'] = ['name' => $cat[$key]['name'], 'search' => !empty($cat[$key]['search'])] + (array) $r['data'];
                }
                $out[$g] = $r;
                break;
            case $g === 'rssmine':
                $p = $rows('prefs')[0] ?? ['feeds' => [], 'keywords' => [], 'tabs' => []];
                $out[$g] = $good(ws_rss_mine((array) $p['feeds'], (array) $p['keywords'], (array) $p['tabs']));
                break;
            default:
                $out[$g] = $fail();
        }
    }
    return $out;
}

/**
 * The person's own feeds, one stream: their typed feeds plus the built-in feeds whose widgets they have on, merged
 * newest first, each item naming its feed, and items holding a watch word marked.
 */
function ws_rss_mine(array $feeds, array $keywords, array $tabs): array
{
    $sources = [];
    foreach (array_slice($feeds, 0, 12) as $url) {
        $r = feed_read_url((string) $url);
        $host = (string) parse_url((string) $url, PHP_URL_HOST);
        $sources[] = ['url' => $url, 'name' => ($r['data']['title'] ?? '') ?: $host, 'ok' => $r['ok'], 'stale' => $r['stale'],
                      'items' => $r['ok'] ? (array) ($r['data']['items'] ?? []) : []];
    }
    $byTab = ['rsswater' => 'water', 'rsspower' => 'power', 'rssphilstar' => 'philstar', 'rssrappler' => 'rappler', 'rssgma' => 'gma',
              'rssgdacs' => 'gdacs', 'rsswho' => 'who', 'rssusgs' => 'usgs', 'fuel' => 'fuel'];
    $cat = feed_catalogue();
    foreach ($tabs as $t) {
        if (!isset($byTab[$t])) continue;
        $key = $byTab[$t];
        $r = feed_read_named($key);
        $sources[] = ['url' => null, 'key' => $key, 'name' => $cat[$key]['name'], 'ok' => $r['ok'], 'stale' => $r['stale'],
                      'items' => $r['ok'] ? (array) ($r['data']['items'] ?? []) : []];
    }
    $words = array_values(array_filter(array_map(static fn ($w) => trim((string) $w), $keywords), static fn ($w) => $w !== ''));
    $stream = [];
    foreach ($sources as $s) {
        foreach (array_slice($s['items'], 0, 10) as $it) {
            $hit = [];
            foreach ($words as $w) {
                if (mb_stripos($it['t'] . ' ' . $it['sum'], $w) !== false) { $hit[] = $w; }
            }
            $stream[] = $it + ['feed' => $s['name'], 'match' => $hit];
        }
    }
    usort($stream, static fn ($a, $b) => strcmp((string) ($b['at'] ?? ''), (string) ($a['at'] ?? '')));
    return [
        'feeds'   => array_map(static fn ($s) => ['url' => $s['url'], 'key' => $s['key'] ?? null, 'name' => $s['name'], 'ok' => $s['ok'],
                                                  'stale' => $s['stale'], 'items' => array_slice($s['items'], 0, 8)], $sources),
        'stream'  => array_slice($stream, 0, 40),
        'matches' => array_values(array_slice(array_filter($stream, static fn ($i) => $i['match'] !== []), 0, 20)),
        'keywords' => $words,
    ];
}
