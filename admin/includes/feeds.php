<?php
/**
 * Reading the outside world for the Workspace widgets (17 Oct 2026): weather, the sea, quakes, holidays and RSS.
 *
 * The browser never calls these hosts itself (the portal's content-security policy lists the few it may talk to); the
 * portal reads them here, keeps each answer for a while in its temp folder, and keeps the last good copy so a source
 * that is down shows the older reading, marked stale, instead of nothing.
 *
 * Two ways to fetch:
 *   feed_get()            a fixed address written in this code (Open-Meteo, USGS, Nager.Date, the built-in feeds)
 *   feed_get_untrusted()  an address a staff member typed (their own RSS feed): https only, port 443, every host it
 *                         resolves to must be a public address, each redirect is checked again, the connection is pinned
 *                         to the address that was checked, and the answer is capped at 2 MB. This is what stops a
 *                         typed address from reaching the portal's own network.
 */
declare(strict_types=1);

const FEED_MAX_BYTES = 2_000_000;
const FEED_UA        = 'SmartSumbong-Barangay183/1.0 (barangay staff workspace)';

function feed_cache_path(string $key): string
{
    $dir = sys_get_temp_dir() . '/ss-feeds';
    if (!is_dir($dir)) {
        @mkdir($dir, 0700, true);
    }
    return $dir . '/' . preg_replace('/[^a-z0-9_-]/i', '_', $key) . '.json';
}

/**
 * The cached answer for $key if younger than $ttl seconds, else $make()'s fresh one (saved), else the last good copy
 * marked stale. $make returns null on failure.
 *
 * @return array{ok:bool, stale:bool, at:?string, data:mixed}
 */
function feed_cached(string $key, int $ttl, callable $make): array
{
    $file = feed_cache_path($key);
    $old  = null;
    if (is_file($file)) {
        $old = json_decode((string) @file_get_contents($file), true);
        if (is_array($old) && filemtime($file) > time() - $ttl) {
            return ['ok' => true, 'stale' => false, 'at' => $old['at'] ?? null, 'data' => $old['data'] ?? null];
        }
    }
    $fresh = null;
    try {
        $fresh = $make();
    } catch (Throwable) {
        $fresh = null;
    }
    if ($fresh !== null) {
        $at = gmdate('c');
        @file_put_contents($file, json_encode(['at' => $at, 'data' => $fresh], JSON_UNESCAPED_UNICODE), LOCK_EX);
        return ['ok' => true, 'stale' => false, 'at' => $at, 'data' => $fresh];
    }
    if (is_array($old)) {
        return ['ok' => true, 'stale' => true, 'at' => $old['at'] ?? null, 'data' => $old['data'] ?? null];
    }
    return ['ok' => false, 'stale' => false, 'at' => null, 'data' => null, 'why' => mb_substr((string) ($GLOBALS['ss_feed_why'] ?? ''), 0, 120)];
}

/** Shared cURL options: https only, short timeouts, a cap on the size of the answer. */
function feed_curl_base(string $url, int $timeout, array $headers, ?string &$body): CurlHandle
{
    $body = '';
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => false,
        CURLOPT_TIMEOUT        => $timeout,
        CURLOPT_CONNECTTIMEOUT => 4,
        CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
        CURLOPT_USERAGENT      => FEED_UA,
        CURLOPT_HTTPHEADER     => $headers ?: ['Accept: application/json, application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.5'],
        CURLOPT_ENCODING       => '',
        CURLOPT_WRITEFUNCTION  => static function ($ch, string $chunk) use (&$body): int {
            if (strlen($body) + strlen($chunk) > FEED_MAX_BYTES) {
                return 0;   // too big: stop reading (the transfer then fails)
            }
            $body .= $chunk;
            return strlen($chunk);
        },
    ]);
    return $ch;
}

/** GET a fixed, trusted address. Null on any failure or a non-200 answer. */
function feed_get(string $url, int $timeout = 8, array $headers = []): ?string
{
    $body = '';
    $ch = feed_curl_base($url, $timeout, $headers, $body);
    curl_setopt_array($ch, [CURLOPT_FOLLOWLOCATION => true, CURLOPT_MAXREDIRS => 3, CURLOPT_REDIR_PROTOCOLS => CURLPROTO_HTTPS]);
    $ok   = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $good = $ok !== false && $code === 200 && $body !== '';
    $GLOBALS['ss_feed_why'] = $good ? '' : ($ok === false ? curl_error($ch) : 'HTTP ' . $code);
    return $good ? $body : null;
}

/** GET JSON from a fixed address, decoded to an array; null on failure. */
function feed_json(string $url, int $timeout = 8): ?array
{
    $raw = feed_get($url, $timeout, ['Accept: application/json']);
    $j = $raw !== null ? json_decode($raw, true) : null;
    return is_array($j) ? $j : null;
}

/** True when $ip is a public unicast address (not private, loopback, link-local, reserved, multicast or mapped). */
function feed_ip_public(string $ip): bool
{
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false) {
        return false;
    }
    // ranges PHP's flags let through
    $bad = ['100.64.0.0/10', '192.0.0.0/24', '192.0.2.0/24', '198.18.0.0/15', '198.51.100.0/24', '203.0.113.0/24',
            '224.0.0.0/4', '::ffff:0:0/96', '64:ff9b::/96', '2001:db8::/32', 'fc00::/7', 'fe80::/10', 'ff00::/8'];
    foreach ($bad as $cidr) {
        if (feed_ip_in($ip, $cidr)) {
            return false;
        }
    }
    return true;
}

function feed_ip_in(string $ip, string $cidr): bool
{
    [$net, $bits] = explode('/', $cidr);
    $a = @inet_pton($ip); $b = @inet_pton($net);
    if ($a === false || $b === false || strlen($a) !== strlen($b)) {
        return false;
    }
    $bits = (int) $bits;
    $bytes = intdiv($bits, 8); $rem = $bits % 8;
    if (strncmp($a, $b, $bytes) !== 0) {
        return false;
    }
    if ($rem === 0) {
        return true;
    }
    $mask = chr((0xFF << (8 - $rem)) & 0xFF);
    return (($a[$bytes] & $mask) === ($b[$bytes] & $mask));
}

/**
 * Checks an address a person typed. Returns [host, ip] to connect to, or null when it may not be fetched: not https,
 * a port other than 443, a user name or password in it, a bare IP address, or a host that resolves to anything that is
 * not a public address.
 *
 * @return array{0:string,1:string}|null
 */
function feed_url_allowed(string $url): ?array
{
    if (strlen($url) > 500 || !preg_match('#^https://#i', $url)) {
        return null;
    }
    $p = parse_url($url);
    if (!$p || strtolower($p['scheme'] ?? '') !== 'https' || empty($p['host']) || isset($p['user']) || isset($p['pass'])) {
        return null;
    }
    if (isset($p['port']) && (int) $p['port'] !== 443) {
        return null;
    }
    $host = strtolower(rtrim($p['host'], '.'));
    if (filter_var(trim($host, '[]'), FILTER_VALIDATE_IP) !== false || !preg_match('/^[a-z0-9.-]+\.[a-z]{2,}$/', $host)
        || in_array($host, ['localhost'], true) || str_ends_with($host, '.local') || str_ends_with($host, '.internal')) {
        return null;
    }
    $ips = [];
    foreach ((array) @dns_get_record($host, DNS_A | DNS_AAAA) as $r) {
        if (!empty($r['ip']))   { $ips[] = $r['ip']; }
        if (!empty($r['ipv6'])) { $ips[] = $r['ipv6']; }
    }
    if (!$ips) {
        $v4 = @gethostbynamel($host);
        $ips = is_array($v4) ? $v4 : [];
    }
    if (!$ips) {
        return null;
    }
    foreach ($ips as $ip) {
        if (!feed_ip_public($ip)) {
            return null;   // any private answer refuses the host: DNS can hand out a different one next time
        }
    }
    return [$host, $ips[0]];
}

/** GET an address a person typed, safely (see the top of this file). Null when refused or on any failure. */
function feed_get_untrusted(string $url, int $timeout = 8): ?string
{
    for ($hop = 0; $hop < 4; $hop++) {
        $ok = feed_url_allowed($url);
        if (!$ok) {
            return null;
        }
        [$host, $ip] = $ok;
        $body = '';
        $ch = feed_curl_base($url, $timeout, [], $body);
        curl_setopt_array($ch, [
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_RESOLVE        => [$host . ':443:' . (str_contains($ip, ':') ? '[' . $ip . ']' : $ip)],
            CURLOPT_HEADER         => false,
        ]);
        $res  = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $next = (string) curl_getinfo($ch, CURLINFO_REDIRECT_URL);
        if ($res === false) {
            return null;
        }
        if (in_array($code, [301, 302, 303, 307, 308], true) && $next !== '') {
            $url = $next;
            continue;
        }
        return ($code === 200 && $body !== '') ? $body : null;
    }
    return null;
}

/**
 * Reads RSS 2.0, RSS 1.0 (RDF) or Atom into plain items: title, link (http or https only), when, a short summary and
 * the publisher where the feed names one (Google News does). Refuses documents that declare entities.
 *
 * @return array{title:string, items:list<array{t:string, link:string, at:?string, sum:string, src:string}>}|null
 */
function feed_parse(string $xml, int $max = 20): ?array
{
    if (preg_match('/<!ENTITY/i', $xml)) {
        return null;
    }
    $prev = libxml_use_internal_errors(true);
    $doc = simplexml_load_string($xml, 'SimpleXMLElement', LIBXML_NONET | LIBXML_NOCDATA | LIBXML_COMPACT);
    libxml_clear_errors();
    libxml_use_internal_errors($prev);
    if ($doc === false) {
        return null;
    }
    $clean = static function ($s, int $len): string {
        // descriptions are often escaped HTML: decode, drop the tags, decode what is left
        $s = html_entity_decode(strip_tags(html_entity_decode((string) $s, ENT_QUOTES | ENT_HTML5, 'UTF-8')), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $s = trim((string) preg_replace('/\s+/u', ' ', $s));
        return mb_strlen($s) > $len ? rtrim(mb_substr($s, 0, $len - 1)) . '…' : $s;
    };
    $link = static fn ($s): string => preg_match('#^https?://#i', trim((string) $s)) ? trim((string) $s) : '';
    $when = static function ($s): ?string {
        $s = trim((string) $s);
        if ($s === '') return null;
        try { return (new DateTimeImmutable($s))->format(DATE_ATOM); } catch (Throwable) { return null; }
    };

    $items = [];
    $title = '';
    $root = $doc->getName();
    if ($root === 'feed') {                       // Atom
        $title = $clean($doc->title, 120);
        foreach ($doc->entry as $e) {
            $href = '';
            foreach ($e->link as $l) {
                $rel = (string) ($l['rel'] ?? 'alternate');
                if ($rel === 'alternate' || $href === '') { $href = (string) $l['href']; }
            }
            $items[] = ['t' => $clean($e->title, 200), 'link' => $link($href), 'at' => $when($e->updated ?: $e->published),
                        'sum' => $clean($e->summary ?: $e->content, 240), 'src' => $clean($e->author->name ?? '', 80)];
            if (count($items) >= $max) break;
        }
    } else {                                      // RSS 2.0 (channel/item) or RSS 1.0 (rdf:RDF/item)
        $ch = $doc->channel ?? null;
        $title = $clean($ch->title ?? '', 120);
        $list = ($ch && count($ch->item)) ? $ch->item : (count($doc->item) ? $doc->item : $doc->children('http://purl.org/rss/1.0/')->item);
        foreach ($list as $it) {
            $dc = $it->children('http://purl.org/dc/elements/1.1/');
            $items[] = ['t' => $clean($it->title, 200), 'link' => $link($it->link), 'at' => $when($it->pubDate ?: $dc->date),
                        'sum' => $clean($it->description, 240), 'src' => $clean($it->source ?? '', 80)];
            if (count($items) >= $max) break;
        }
    }
    $items = array_values(array_filter($items, static fn ($i) => $i['t'] !== ''));
    return ['title' => $title, 'items' => $items];
}

/** A Google News search as RSS, Philippine edition. */
function feed_gnews(string $q): string
{
    return 'https://news.google.com/rss/search?' . http_build_query(['q' => $q, 'hl' => 'en-PH', 'gl' => 'PH', 'ceid' => 'PH:en']);
}

/**
 * The feeds the portal knows by name. Each was answering on 17 Oct 2026 except where noted. 'search' marks a news
 * search: the items are news stories that mention the subject, never an official notice, and say who published them.
 *
 * @return array<string, array{name:string, url:string, search?:bool, ua?:bool}>
 */
function feed_catalogue(): array
{
    return [
        'philstar' => ['name' => 'Philstar', 'url' => 'https://www.philstar.com/rss/headlines'],
        'rappler'  => ['name' => 'Rappler', 'url' => 'https://www.rappler.com/feed/'],
        'gma'      => ['name' => 'GMA News', 'url' => 'https://data.gmanetwork.com/gno/rss/news/feed.xml'],
        'inquirer' => ['name' => 'Inquirer', 'url' => 'https://newsinfo.inquirer.net/feed', 'ua' => true],
        'gdacs'    => ['name' => 'GDACS', 'url' => 'https://www.gdacs.org/xml/rss.xml'],
        'who'      => ['name' => 'WHO', 'url' => 'https://www.who.int/rss-feeds/news-english.xml'],
        'usgs'     => ['name' => 'USGS', 'url' => 'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_week.atom'],
        // PNA publishes no feed and the DOH site sits behind a bot check: their stories come through a news search.
        // Searches carry a window (when:Nd) so an old notice never reads as today's.
        'pna'      => ['name' => 'PNA', 'url' => feed_gnews('site:pna.gov.ph when:2d'), 'search' => true],
        'doh'      => ['name' => 'DOH', 'url' => feed_gnews('"Department of Health" advisory Philippines when:14d'), 'search' => true],
        'water'    => ['name' => 'Maynilad', 'url' => feed_gnews('Maynilad water interruption Pasay when:14d'), 'search' => true],
        'power'    => ['name' => 'Meralco', 'url' => feed_gnews('Meralco power interruption Pasay when:30d'), 'search' => true],
        'fuel'     => ['name' => 'Oil prices', 'url' => feed_gnews('oil price rollback OR hike Philippines when:7d'), 'search' => true],
    ];
}

/** One built-in feed, cached ten minutes. */
function feed_read_named(string $key): array
{
    $cat = feed_catalogue();
    if (!isset($cat[$key])) {
        return ['ok' => false, 'stale' => false, 'at' => null, 'data' => null];
    }
    $f = $cat[$key];
    return feed_cached('rss-' . $key, 600, static function () use ($f): ?array {
        $headers = !empty($f['ua'])
            ? ['Accept: application/rss+xml, application/xml;q=0.9, */*;q=0.8', 'User-Agent: Mozilla/5.0 (compatible; SmartSumbong/1.0; +barangay staff workspace)']
            : [];
        $raw = feed_get($f['url'], 8, $headers);
        return $raw !== null ? feed_parse($raw) : null;
    });
}

/** A feed a person added, cached ten minutes, fetched with the address checks. */
function feed_read_url(string $url): array
{
    return feed_cached('rss-u-' . sha1($url), 600, static function () use ($url): ?array {
        $raw = feed_get_untrusted($url);
        return $raw !== null ? feed_parse($raw) : null;
    });
}
