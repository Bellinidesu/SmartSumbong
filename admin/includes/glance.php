<?php
/**
 * "At a glance": the public side panel of the sign-in pages (15 Nov 2026, Ace).
 *
 * Anyone who opens the portal's address sees it, signed in or not, so it holds public information only: the weather over Barangay 183 (Open-Meteo),
 * the warning PAGASA has out for Metro Manila (the same reader the map uses), the flood advisory, the hotlines the barangay put on its tarpaulin (public by
 * design, migration 0025) and a couple of Pasay headlines. No case, no person, no count from the barangay's own data ever goes through here.
 *
 * Every source is read by the server and kept five to ten minutes in its temp folder (feeds.php, hazards.php), with the last good copy served when a source is
 * down, so the page itself costs nothing and a hundred visitors make one request out. A source that fails is simply left out; the panel says so.
 */
declare(strict_types=1);

require_once __DIR__ . '/feeds.php';
require_once __DIR__ . '/hazards.php';

/** Open-Meteo's weather for Barangay 183: the reading now and today's sunrise and sunset. */
function glance_weather(): ?array
{
    $url = 'https://api.open-meteo.com/v1/forecast?' . http_build_query([
        'latitude' => HZ_LAT, 'longitude' => HZ_LNG, 'timezone' => 'Asia/Manila', 'forecast_days' => 1,
        'current' => 'temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m',
        'daily'   => 'sunrise,sunset',
    ]);
    $r = feed_cached('glance-wx-v1', 600, static function () use ($url): ?array {
        $j = feed_json($url);
        return isset($j['current']['temperature_2m'], $j['daily']['sunrise'][0], $j['daily']['sunset'][0]) ? $j : null;
    });
    return $r['ok'] && is_array($r['data']) ? $r['data'] : null;
}

/** WMO weather code to the scene's four kinds of weather. */
function glance_kind(int $code): string
{
    if ($code >= 95) return 'storm';
    if (($code >= 51 && $code <= 67) || ($code >= 80 && $code <= 82)) return 'rain';
    if ($code === 0 || $code === 1) return 'clear';
    return 'cloudy';   // partly cloudy, overcast, fog
}

/** The hour as the scene draws it: dawn, day, golden (late afternoon), dusk or night, from today's sunrise and sunset. */
function glance_phase(?array $wx, DateTimeImmutable $now): string
{
    if (!$wx) {
        $h = (int) $now->format('G');
        return $h < 5 ? 'night' : ($h < 7 ? 'dawn' : ($h < 15 ? 'day' : ($h < 17 ? 'golden' : ($h < 19 ? 'dusk' : 'night'))));
    }
    $tz = new DateTimeZone('Asia/Manila');
    $rise = (new DateTimeImmutable($wx['daily']['sunrise'][0], $tz))->getTimestamp();
    $set  = (new DateTimeImmutable($wx['daily']['sunset'][0], $tz))->getTimestamp();
    $t = $now->getTimestamp();
    if ($t < $rise - 2700 || $t > $set + 3000) return 'night';
    if ($t < $rise + 3600) return 'dawn';
    if ($t < $set - 7200) return 'day';
    if ($t < $set - 1200) return 'golden';
    return 'dusk';
}

/** The strongest PAGASA warning that names Metro Manila, and whether a flood advisory is out. */
function glance_warning(array $hz): array
{
    $best = null; $flood = false;
    foreach ((array) ($hz['warnings'] ?? []) as $w) {
        if (empty($w['metro'])) continue;
        $type = strtolower((string) ($w['type'] ?? ''));
        if (str_contains($type, 'flood')) $flood = true;
        $kind = str_contains($type, 'thunder') ? 'thunder' : (str_contains($type, 'rain') ? 'rain' : (str_contains($type, 'flood') ? 'flood' : ''));
        if ($kind === '' || $kind === 'flood') continue;
        $lvl = (int) ($w['level'] ?? 0);
        if ($best === null || $lvl > $best['level']) {
            $best = ['level' => $lvl, 'kind' => $kind, 'until' => (string) ($w['expires'] ?? '')];
        }
    }
    $sig = $hz['cyclone']['signal'] ?? null;
    if ($sig && (int) $sig > 0) { $best = ['level' => 3, 'kind' => 'wind', 'signal' => (int) $sig, 'until' => '']; }
    return ['warn' => $best, 'flood' => $flood];
}

/** The hotlines the barangay shows the public: up to four groups and three numbers each. */
function glance_hotlines(): array
{
    $r = feed_cached('glance-hot-v1', 600, static function (): ?array {
        $rows = (new Supabase(null))->select('hotline_groups', [
            'select' => 'name,sort_order,parent_id,hotline_numbers(label,number,sort_order,is_active)', 'is_active' => 'is.true', 'order' => 'sort_order.asc', 'limit' => '12',
        ]);
        $out = [];
        foreach ((array) $rows as $g) {
            $nums = [];
            $list = (array) ($g['hotline_numbers'] ?? []);
            usort($list, static fn ($a, $b) => ((int) ($a['sort_order'] ?? 0)) <=> ((int) ($b['sort_order'] ?? 0)));
            foreach ($list as $n) {
                if (empty($n['is_active']) || trim((string) ($n['number'] ?? '')) === '') continue;
                $num = (string) $n['number'];
                $nums[] = ['label' => mb_substr((string) ($n['label'] ?? ''), 0, 60), 'number' => mb_substr($num, 0, 40), 'tel' => preg_replace('/[^0-9+*#,]/', '', $num)];
                if (count($nums) >= 3) break;
            }
            if ($nums) $out[] = ['name' => mb_substr((string) $g['name'], 0, 60), 'numbers' => $nums];
            if (count($out) >= 4) break;
        }
        return $out ?: null;
    });
    return $r['ok'] && is_array($r['data']) ? $r['data'] : [];
}

/** Two Pasay headlines from a public news search, with who published them. */
function glance_news(): array
{
    $r = feed_cached('glance-news-v1', 900, static function (): ?array {
        $raw = feed_get(feed_gnews('Pasay when:3d'), 8);
        $p = $raw !== null ? feed_parse($raw, 6) : null;
        if (!$p || empty($p['items'])) return null;
        $out = [];
        foreach ($p['items'] as $i) {
            $title = (string) $i['t']; $src = (string) $i['src'];
            // a Google News title ends " - Publisher": the publisher is the source, the rest the headline
            if ($src === '' && preg_match('/^(.*)\s+-\s+([^-]{2,40})$/u', $title, $m)) { $title = $m[1]; $src = $m[2]; }
            $out[] = ['t' => mb_substr($title, 0, 140), 'src' => mb_substr($src, 0, 40), 'url' => (string) $i['link']];
            if (count($out) >= 2) break;
        }
        return $out ?: null;
    });
    return $r['ok'] && is_array($r['data']) ? $r['data'] : [];
}

/**
 * A fixed answer for the test portal and for looking at every mood of the picture (never on the live site: it needs GLANCE_OFFLINE=1 in the environment).
 * glance.php?demo=<phase>-<weather>, for example night-storm; without demo it is the sample for the clock's hour.
 */
function glance_demo(string $spec): array
{
    [$ph, $wx] = array_pad(explode('-', $spec, 2), 2, 'clear');
    $ph = in_array($ph, ['dawn', 'day', 'golden', 'dusk', 'night'], true) ? $ph : glance_phase(null, new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')));
    $wx = in_array($wx, ['clear', 'cloudy', 'rain', 'storm'], true) ? $wx : 'clear';
    $wet = $wx === 'rain' || $wx === 'storm';
    return [
        'ok' => true, 'at' => gmdate('c'), 'phase' => $ph, 'when' => ['dawn' => '6:10 AM', 'day' => '11:15 AM', 'golden' => '4:45 PM', 'dusk' => '6:05 PM', 'night' => '9:05 PM'][$ph],
        'now' => ['temp' => 30 - ($wet ? 4 : 0), 'feels' => 36 - ($wet ? 3 : 0), 'wind' => $wet ? 22 : 12, 'kind' => $wx],
        'warn' => $wet ? ['level' => 2, 'kind' => $wx === 'storm' ? 'thunder' : 'rain', 'until' => gmdate('c', time() + 3 * 3600)] : null,
        'flood' => false,
        'hot' => [['name' => 'Barangay hall', 'numbers' => [['label' => 'Hall', 'number' => '(02) 8000 0000', 'tel' => '0280000000']]], ['name' => 'Fire', 'numbers' => [['label' => 'Fire station', 'number' => '160', 'tel' => '160']]], ['name' => 'Police', 'numbers' => [['label' => 'Police', 'number' => '117', 'tel' => '117']]]],
        'news' => [['t' => 'A headline from a public news feed', 'src' => 'Sample', 'url' => 'https://example.com/a'], ['t' => 'A second headline, with its source', 'src' => 'Sample', 'url' => 'https://example.com/b']],
    ];
}

/** Everything the panel shows, as one small answer. A part that could not be read is left out (null or empty). */
function glance_read(): array
{
    if (env('GLANCE_OFFLINE', '') === '1') { return glance_demo((string) ($_GET['demo'] ?? '')); }
    $tz  = new DateTimeZone('Asia/Manila');
    $now = new DateTimeImmutable('now', $tz);
    $wx  = glance_weather();
    $hz  = function_exists('hazards_read') ? (array) hazards_read() : [];
    $w   = glance_warning($hz);
    $c   = $wx['current'] ?? null;
    return [
        'ok'    => true,
        'at'    => gmdate('c'),
        'phase' => glance_phase($wx, $now),
        'when'  => $now->format('g:i A'),
        'now'   => $c ? [
            'temp'  => (int) round((float) $c['temperature_2m']),
            'feels' => (int) round((float) ($c['apparent_temperature'] ?? $c['temperature_2m'])),
            'wind'  => (int) round((float) ($c['wind_speed_10m'] ?? 0)),
            'kind'  => glance_kind((int) ($c['weather_code'] ?? 0)),
        ] : null,
        'warn'  => $w['warn'],
        'flood' => $hz ? $w['flood'] : null,   // null: PAGASA could not be read, so nothing is claimed
        'hot'   => glance_hotlines(),
        'news'  => glance_news(),
    ];
}
