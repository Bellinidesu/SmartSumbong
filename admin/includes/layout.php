<?php
/**
 * Shared chrome. Every protected page calls layout_head() and
 * layout_foot() around its own markup.
 *
 * Nav items and their order follow the Figma sidebar exactly.
 */
declare(strict_types=1);

function nav_items(): array
{
    $items = [
        ['dashboard.php',  t('Dashboard', 'Dashboard'),                       'i-dash'],
        ['summary.php',    t('Report Summary', 'Buod ng mga Ulat'),           'i-doc'],
        ['spatial.php',    t('Spatial Distribution', 'Mapa ng mga Sumbong'),  'i-map'],
        ['cases.php',      t('Case Reports', 'Mga Sumbong'),                  'i-chat'],
        ['workspace.php',  t('Workspace', 'Tablero ng Gawain'),               'i-board'],
        ['notifications.php', t('Notifications', 'Mga Abiso'),                'i-bell'],
        ['inbox.php',      t('Inbox', 'Mga Liham'),                               'i-send'],
        ['residents.php',  t('Residents', 'Mga Residente'),                   'i-users'],
        ['personnel.php',  t('Personnel', 'Mga Tanod'),                       'i-shield'],
        ['administrative-services.php', t('Administrative Services', 'Mga Serbisyong Pang-admin'), 'i-brief'],
        ['control-room.php', t('Control Room', 'Silid-Kontrol'), 'i-board'],
        ['settings.php',   t('Settings', 'Mga Setting'),                      'i-gear'],
    ];
    // a part that is switched off (feature_switches, 0144) has no menu entry
    return array_values(array_filter($items, static fn (array $i): bool => ($i[0] !== 'workspace.php' || feature_on('workspace')) && page_allowed($i[0])));
}

/** An icon from the preview's set (includes/p_sprite.svg). */
function p_icon(string $id, int $size = 0): string
{
    $wh = $size ? ' width="' . $size . '" height="' . $size . '"' : '';
    return '<svg' . $wh . ' aria-hidden="true"><use href="#' . e($id) . '"/></svg>';
}

/** Kept for pages still drawing the old icon names (doc_print, certificate). */
function nav_icon(string $name): string
{
    $map = ['chart' => 'i-dash', 'doc' => 'i-doc', 'map' => 'i-map', 'chat' => 'i-chat', 'users' => 'i-users',
            'user' => 'i-shield', 'badge' => 'i-brief', 'gear' => 'i-gear', 'out' => 'i-out', 'search' => 'i-search'];
    return p_icon($map[$name] ?? 'i-doc');
}

/** Page links for a list: Previous, a window of numbers, Next. $param is the query key that holds the page. */
function pager(int $total, int $page, string $param = 'page', ?int $per = null, string $anchor = ''): string
{
    $per = $per ?? (defined('PER_PAGE') ? PER_PAGE : 15);
    $pages = max(1, (int) ceil($total / $per));
    if ($pages <= 1) { return ''; }
    $href = function (int $n) use ($param, $anchor): string { $q = $_GET; $q[$param] = $n; return '?' . http_build_query($q) . ($anchor !== '' ? '#' . $anchor : ''); };
    $from = max(1, min($page - 2, $pages - 4)); $to = min($pages, $from + 4);
    $o = '<nav class="ss-pager" aria-label="' . e(t('Pages', 'Mga pahina')) . '">';
    $o .= $page > 1 ? '<a href="' . e($href($page - 1)) . '" rel="prev">&lsaquo; ' . e(t('Previous', 'Nakaraan')) . '</a>' : '<span class="off">&lsaquo; ' . e(t('Previous', 'Nakaraan')) . '</span>';
    if ($from > 1) { $o .= '<a href="' . e($href(1)) . '">1</a>' . ($from > 2 ? '<span class="gap">&hellip;</span>' : ''); }
    for ($i = $from; $i <= $to; $i++) {
        $o .= $i === $page ? '<span class="on" aria-current="page">' . $i . '</span>' : '<a href="' . e($href($i)) . '">' . $i . '</a>';
    }
    if ($to < $pages) { $o .= ($to < $pages - 1 ? '<span class="gap">&hellip;</span>' : '') . '<a href="' . e($href($pages)) . '">' . $pages . '</a>'; }
    $o .= $page < $pages ? '<a href="' . e($href($page + 1)) . '" rel="next">' . e(t('Next', 'Susunod')) . ' &rsaquo;</a>' : '<span class="off">' . e(t('Next', 'Susunod')) . ' &rsaquo;</span>';
    $from1 = ($page - 1) * $per + 1; $to1 = min($total, $page * $per);
    return $o . '<span class="of">' . $from1 . '&ndash;' . $to1 . ' ' . e(t('of', 'sa')) . ' ' . $total . '</span></nav>';
}

/** The engine's brain as a small icon, for places a square button or tile needs one (the map's dock, a SMART notification). */
function smart_brain(int $size = 20): string
{
    return '<svg class="ss-brain-ico" width="' . $size . '" height="' . $size . '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 2.8A3 3 0 0 0 5.4 13 3 3 0 0 0 7 18a3 3 0 0 0 5-1.2V5.5A2.5 2.5 0 0 0 9 4z"/><path d="M15 4a3 3 0 0 1 3 3 3 3 0 0 1 2 2.8 3 3 0 0 1-1.4 3.2A3 3 0 0 1 17 18a3 3 0 0 1-5-1.2"/><path d="M12 8v9M9 9.5h-1.5M15 9.5h1.5M9 14h-1M15 14h1"/></svg>';
}

/** The SMART engine's mark. Its glow is made for a dark ground, so it always sits on its own dark chip, in either theme. */
function smart_logo(int $height = 34): string
{
    $w = (int) round($height * 840 / 328);
    return '<span class="ss-engine" role="img" aria-label="SMART engine"><img src="assets/img/smart-engine.webp" width="' . $w . '" height="' . $height . '" alt="" decoding="async"></span>';
}

/** SMART's level for a case, always with its word beside the colour (Urgent red, High orange, Normal blue, Low grey). */
function smart_badge(?array $tr): string
{
    if (!$tr || empty($tr['effective_level'])) { return '<span class="p-sub">' . e(t('Not scored', 'Walang marka')) . '</span>'; }
    $lv = $tr['effective_level'];
    $cls = ['urgent' => 'denied', 'high' => 'pending', 'normal' => 'progress', 'low' => 'grey'][$lv] ?? 'grey';
    $lab = ['urgent' => t('Urgent', 'Apurahan'), 'high' => t('High', 'Mataas'), 'normal' => t('Normal', 'Karaniwan'), 'low' => t('Low', 'Mababa')][$lv] ?? $lv;
    $o = '<span class="p-badge p-b-' . $cls . '">' . e($lab) . '</span><small class="ss-score"> ' . (int) $tr['score'] . '</small>';
    if (!empty($tr['override_level'])) { $o .= '<small class="ss-set" title="' . e(t('Set by an admin', 'Itinakda ng admin')) . '">' . e(t('set by admin', 'itinakda ng admin')) . '</small>'; }
    if ((int) ($tr['possible_duplicates'] ?? 0) > 0) { $o .= '<span class="p-badge p-b-violet ss-dup">' . e(t('Possible duplicate', 'Maaaring doble')) . '</span>'; }
    return $o;
}
function waiting_text(?string $iso): string
{
    if (!$iso) { return ''; }
    $h = (int) floor((time() - strtotime($iso)) / 3600);
    return $h < 1 ? t('under 1 h', 'wala pang 1 oras') : ($h < 48 ? $h . ' ' . t('h', 'oras') : (int) floor($h / 24) . ' ' . t('days', 'araw'));
}


/** The committees, as [label]; the key is what the database stores (0130). Since 0145 they come from the committees table
    (its short names), which a super admin edits; the list below is only the fallback if it cannot be read. */
function committee_labels(): array
{
    $out = [];
    foreach (committees_all() as $k => $c) { $out[$k] = [t((string) $c['short_en'], (string) $c['name_fil'])]; }
    return $out ?: [
        'peace_order'       => [t('Peace and Order', 'Kapayapaan at Kaayusan')],
        'health_sanitation' => [t('Health and Sanitation', 'Kalusugan at Kalinisan')],
        'environment'       => [t('Environment', 'Kapaligiran')],
    ];
}

/** The colour of each committee's dot (Ace, 14 Oct: shown only on a Kagawad's row in Settings and on a case's page). */
function committee_colour(?string $c): string
{
    // 0150: the colour a super admin chose for the committee; the old fixed list only answers when the table cannot be read
    $chosen = committees_all()[(string) $c]['colour'] ?? null;
    if (is_string($chosen) && preg_match('/^#[0-9A-Fa-f]{6}$/', $chosen)) return strtoupper($chosen);
    return [
        'peace_order' => '#D32F2F', 'health_sanitation' => '#1E9E4A', 'education' => '#039BE5', 'infrastructure' => '#6D4C41',
        'environment' => '#00838F', 'women_family' => '#D81B60', 'youth_sports' => '#8E24AA', 'agriculture' => '#7CB342',
        'appropriations' => '#78909C', 'anti_drug' => '#5C6BC0',
    ][(string) $c] ?? ['#5C6BC0', '#00897B', '#F4511E', '#7CB342', '#8E24AA', '#039BE5'][abs(crc32((string) $c)) % 6];   // a committee made later gets a steady colour
}

/** The colours offered when a super admin makes a committee (0150); the database refuses any that is too close to one taken. */
const COMMITTEE_PALETTE = ['#D32F2F', '#F4511E', '#F9A825', '#7CB342', '#1E9E4A', '#00838F', '#039BE5', '#5C6BC0', '#8E24AA', '#D81B60', '#6D4C41', '#78909C'];

/** The distance between two #RRGGBB colours, as the database measures it (0150): under 70 is "too close". */
function colour_dist(string $a, string $b): float
{
    $c = fn (string $h, int $i) => hexdec(substr($h, 1 + 2 * $i, 2));
    return sqrt(($c($a, 0) - $c($b, 0)) ** 2 + ($c($a, 1) - $c($b, 1)) ** 2 + ($c($a, 2) - $c($b, 2)) ** 2);
}

/** What a colour is too close to, for a committee (null: free), as the database decides it. */
function colour_clash(string $hex, ?string $except = null): ?string
{
    if (colour_dist($hex, barangay()['super_colour'] ?? SUPER_BLUE) < 70) return t('the super admin colour', 'ang kulay ng super admin');
    foreach (committees_all() as $k => $c) {
        if ($k !== $except && !empty($c['active']) && !empty($c['colour']) && colour_dist($hex, (string) $c['colour']) < 70) {
            return sprintf(t('the %s committee', 'ang komite ng %s'), (string) $c['short_en']);
        }
    }
    return null;
}

/**
 * The sidebar's colour for the person signed in (0150, docs/ROLES_AND_PAGES.md section 2): their committee's for a committee
 * admin, so a screenshot says which committee it came from, and the super admin colour for everyone else.
 *
 * @return array{hex:string, label:?string}
 */
function side_colour(): array
{
    if (is_scoped()) {   // a Kagawad or a staff member wears their committee's colour
        $c = committees_all()[(string) (current_admin()['committee'] ?? '')] ?? null;
        if ($c) return ['hex' => committee_colour((string) $c['key']), 'label' => (string) $c['short_en']];
    }
    return ['hex' => strtoupper((string) (barangay()['super_colour'] ?? SUPER_BLUE)), 'label' => null];
}

/**
 * The sidebar's two tones from one colour, the way branding blue makes them (#00308F to #00236A): the same hue, deep, in light;
 * the hue only as a tint over graphite in dark. Branding blue itself keeps the portal's own sidebar. Inline styles are allowed.
 */
function side_colour_style(): string
{
    $hex = side_colour()['hex'];
    if ($hex === SUPER_BLUE) return '';
    [$r, $g, $b] = array_map(fn ($i) => hexdec(substr($hex, 1 + 2 * $i, 2)) / 255, [0, 1, 2]);
    $mx = max($r, $g, $b); $mn = min($r, $g, $b); $d = $mx - $mn; $l = ($mx + $mn) / 2; $h = 0.0; $s = 0.0;
    if ($d > 0) {
        $s = $d / (1 - abs(2 * $l - 1));
        $h = match (true) { $mx === $r => fmod(($g - $b) / $d, 6), $mx === $g => ($b - $r) / $d + 2, default => ($r - $g) / $d + 4 } * 60;
        if ($h < 0) $h += 360;
    }
    $hs = (int) round($h); $sl = (int) round(min($s * 100, 90)); $sd = (int) round(min($s * 100, 30));
    $light = "--p-side-a:hsl($hs $sl% 28%);--p-side-b:hsl($hs $sl% 20%)";
    $dark = "--p-side-a:hsl($hs $sd% 20%);--p-side-b:hsl($hs $sd% 11%)";
    return "<style>:root{{$light}}@media (prefers-color-scheme: dark){:root:not([data-theme=\"light\"]){{$dark}}}:root[data-theme=\"dark\"]{{$dark}}</style>\n";
}

/** Black or white text on a colour, whichever reads. */
function ink_on(string $hex): string
{
    $lin = fn ($v) => ($v /= 255) <= .03928 ? $v / 12.92 : (($v + .055) / 1.055) ** 2.4;
    $lum = .2126 * $lin(hexdec(substr($hex, 1, 2))) + .7152 * $lin(hexdec(substr($hex, 3, 2))) + .0722 * $lin(hexdec(substr($hex, 5, 2)));
    return 1.05 / ($lum + .05) >= 4.5 ? '#FFFFFF' : '#15181D';
}

/** Which rung of the barangay ladder an administrator's position sits on: staff, kagawad or chair. */
function rank_of(?string $role): string
{
    return match ($role) { 'kagawad' => 'kagawad', 'chairman' => 'chair', default => 'staff' };
}

/** A position as a coloured chip, its word always beside the colour. $dot adds the committee for a Kagawad. */
function rank_chip(?string $role, ?string $committee = null, bool $dot = false): string
{
    $rank  = rank_of($role);
    $label = match ($rank) {
        'kagawad' => t('Councilor', 'Kagawad'),
        'chair'   => t('Chairman', 'Punong Barangay'),
        default   => $role === 'secretary' ? t('Secretary', 'Kalihim') : t('Staff', 'Kawani'),
    };
    $o = '<span class="rank' . ($rank === 'chair' ? ' chair' : '') . '" data-r="' . $rank . '"><i></i>' . e($label);
    if ($dot && $rank === 'kagawad' && $committee) {
        $o .= '<span class="cdot" style="--cc:' . committee_colour($committee) . '" aria-hidden="true"></span>' . e(committee_labels()[$committee][0] ?? '');
    }
    return $o . '</span>';
}

function layout_head(string $title, string $active = ''): void
{
    $admin = current_admin();
    $en = lang() === 'en';
    ?><!DOCTYPE html>
<html lang="<?= html_lang() ?>">
<head>
<meta charset="utf-8">
<?= theme_head(false) ?>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>
// Error tracking (0097): this page's script errors are recorded for the
// admins (Settings → System status), at most five per page load.
(function () {
  var left = 5, url = <?= json_encode(supabase_url() . '/rest/v1/rpc/log_portal_error') ?>, key = <?= json_encode(supabase_key()) ?>;
  function send(msg, detail) {
    if (left-- <= 0 || !msg) return;
    try {
      fetch(url, { method: 'POST', keepalive: true, headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_source: 'browser', p_page: location.pathname, p_message: String(msg).slice(0, 500), p_detail: detail ? String(detail).slice(0, 2000) : null }) }).catch(function () {});
    } catch (e) {}
  }
  window.addEventListener('error', function (e) {
    if (e.message) send(e.message, (e.filename || '').split('/').pop() + ':' + e.lineno + ':' + e.colno + (e.error && e.error.stack ? '\n' + e.error.stack : ''));
  });
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason; send('Unhandled: ' + (r && r.message ? r.message : r), r && r.stack);
  });
})();
// Whether a purok boundaries file exists (map-theme.js skips the request if not).
window.SS_ZONES = <?= is_file(__DIR__ . '/../assets/map/zones.geojson') ? 'true' : 'false' ?>;
window.ssThumb = function (u, w, sq) { u = String(u || ''); return /^https:\/\/res\.cloudinary\.com\/[^/]+\/image\/upload\//.test(u) ? u.replace('/image/upload/', '/image/upload/' + (sq ? 'c_fill,g_face,w_' + w + ',h_' + w : 'c_limit,w_' + w) + ',q_auto,f_auto/') : u; };
// Casual name ("Ace Lediac") from the stored formal one ("Lediac, Ace"). Same as display_name().
window.ssName = function (n) { n = String(n == null ? '' : n); var c = n.indexOf(','); return c > 0 ? n.slice(c + 1).trim() + ' ' + n.slice(0, c).trim() : n; };
// The live connections' token (27 Sep 2026). A page starts with the one
// it was loaded with; this hands supabase-js a fresh one from token.php
// before that runs out, so realtime and the polls keep working on a page
// left open for hours. Pass it as createClient's accessToken option.
window.ssAccessToken = function (initial) {
  var token = initial, fetchedAt = Date.now(), pending = null;
  function renew() {
    pending = pending || fetch('token.php', { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) {
        if (r.status === 401) { location.href = 'login.php?expired=1'; return null; }
        return r.ok ? r.json() : null;
      })
      .then(function (d) { if (d && d.token) { token = d.token; fetchedAt = Date.now(); } })
      .catch(function () {})
      .then(function () { pending = null; });
    return pending;
  }
  return function () {
    return Date.now() - fetchedAt > 5 * 60 * 1000
      ? renew().then(function () { return token; })
      : Promise.resolve(token);
  };
};
</script>
<title><?= e($title) ?> — Smart Sumbong | <?= e(barangay()['name']) ?></title>
<meta name="description" content="Smart Sumbong: <?= e(brgy_line()) ?> complaint management portal for barangay staff.">
<link rel="icon" type="image/png" href="assets/img/favicon-64.png">
<link rel="apple-touch-icon" href="assets/img/brgy-183-seal.png">
<meta name="theme-color" content="#00308F">
<link rel="manifest" href="manifest.webmanifest">
<?php // Speed (pass 4): open the database connection and fetch the two
      // main font files while the page is still being read. ?>
<link rel="preconnect" href="<?= e(supabase_url()) ?>" crossorigin>
<link rel="preload" href="assets/vendor/fonts/urbanist-regular.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="assets/vendor/fonts/urbanist-bold.woff2" as="font" type="font/woff2" crossorigin>
<link href="assets/css/fonts.css?v=<?= e(asset_version('fonts.css')) ?>" rel="stylesheet">
<link href="assets/css/p.css?v=<?= e(asset_version('p.css')) ?>" rel="stylesheet">
<link href="assets/css/p-portal.css?v=<?= e(asset_version('p-portal.css')) ?>" rel="stylesheet">
<link href="assets/css/flair.css?v=<?= e(asset_version('flair.css')) ?>" rel="stylesheet">
<link href="assets/css/smart.css?v=<?= e(asset_version('smart.css')) ?>" rel="stylesheet">
<link href="assets/css/shell.css?v=<?= e(asset_version('shell.css')) ?>" rel="stylesheet">
<?= side_colour_style() ?><script src="assets/js/p.js?v=<?= e(asset_version('../js/p.js')) ?>" defer></script>
</head>
<body class="p-body page-<?= e(basename($active, '.php')) ?>">
<?= file_get_contents(__DIR__ . '/p_sprite.svg') ?>
<div id="app" class="p-on">
  <aside class="p-sidebar">
    <button type="button" class="p-edge" id="side-edge" aria-controls="side-nav" aria-expanded="true"
            data-collapse="<?= e(t('Shrink the sidebar', 'Paliitin ang sidebar')) ?>" data-expand="<?= e(t('Expand the sidebar', 'Palakihin ang sidebar')) ?>"
            aria-label="<?= e(t('Shrink the sidebar', 'Paliitin ang sidebar')) ?>" title="<?= e(t('Shrink the sidebar', 'Paliitin ang sidebar')) ?>"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m15 5-7 7 7 7"/></svg></button>
    <div class="p-side-top"><a class="p-brand" href="<?= e(page_allowed('dashboard.php') ? 'dashboard.php' : landing_page()) ?>"><img src="assets/img/logo-wordmark.webp" width="355" height="369" alt="Smart Sumbong"></a></div>
    <?php $sideC = side_colour(); if ($sideC['label'] !== null): ?>
      <?php // 0150: a committee admin's sidebar names the committee, in its colour ?>
      <div class="p-side-com" style="--cc:<?= e($sideC['hex']) ?>;--ci:<?= e(ink_on($sideC['hex'])) ?>" title="<?= e($sideC['label']) ?>"><i aria-hidden="true"></i><span><?= e($sideC['label']) ?></span></div>
    <?php endif; ?>
    <nav class="p-nav" id="side-nav" aria-label="<?= e(t('Main', 'Pangunahin')) ?>">
      <?php $counts = nav_counts(); ?>
      <?php foreach (nav_items() as [$href, $label, $icon]): ?>
        <?php $n = $counts[$href] ?? 0; ?>
        <a href="<?= e($href) ?>" title="<?= e($label) ?>" class="<?= basename($href) === $active ? 'p-active' : '' ?>"<?= basename($href) === $active ? ' aria-current="page"' : '' ?>>
          <?= p_icon($icon) ?><span><?= e($label) ?></span>
          <?php $smartN = $href === 'notifications.php' ? (int) ($counts['notifications_smart'] ?? 0) : 0; ?>
          <?php if ($n > 0 || $smartN > 0): ?>
            <span class="p-rt"><?php if ($smartN > 0): ?><span class="p-brain-pill" title="<?= e(t('Unread notes from the SMART engine', 'May hindi pa nababasang abiso mula sa SMART engine')) ?>"><?= smart_brain(13) ?></span><?php endif; ?><?php if ($n > 0): ?><span class="p-pill<?= $href === 'notifications.php' ? ' p-pill--hot' : '' ?>" title="<?= e((string) $n) ?>"><?= $n > 99 ? '99+' : $n ?></span><?php endif; ?></span>
          <?php endif; ?>
        </a>
      <?php endforeach; ?>
    </nav>
    <div class="p-side-foot">
      <div class="p-side-user<?= $active === 'profile.php' ? ' p-active' : '' ?>" id="side-user">
        <a class="p-side-me" href="profile.php" title="<?= e(t('Edit profile', 'I-edit ang profile')) ?>">
          <?= admin_avatar_html($admin) ?>
          <div class="p-who"><b><?= e(name_or($admin['full_name'] ?? null, t('Administrator', 'Tagapangasiwa'))) ?></b><small><?= e(access_label()) ?></small></div>
        </a>
        <button type="button" title="<?= e(t('Log out', 'Mag-log out')) ?>" aria-label="<?= e(t('Log out', 'Mag-log out')) ?>" data-p-open="p-m-logout"><?= p_icon('i-out', 18) ?></button>
      </div>
    </div>
  </aside>

  <main class="p-main">
<?php
    $storm = storm_state();
    if ($storm): ?>
    <div class="ss-storm ss-storm--page<?= $active === 'spatial.php' ? ' ss-storm--map' : '' ?>" role="status"><span><b><?= e(t('Storm mode', 'Panahon ng bagyo')) ?></b>
      <?= e(t('until', 'hanggang')) ?> <?= e((new DateTimeImmutable((string) $storm['storm_until']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('M j, g:i A')) ?>
      <?= !empty($storm['storm_reason']) ? '· ' . e((string) $storm['storm_reason']) : '' ?>
      <small><?= e(t('Flood zones and flood, live-wire and collapse reports count double.', 'Doble ang bilang ng mga bahaing lugar at ng mga ulat ng baha, live wire at pagguho.')) ?></small></span>
      <?php if (is_super()): // 0145: storm mode is a super admin's setting ?>
      <span class="ss-storm-act">
        <a class="p-btn p-btn-ghost p-btn-sm" href="settings.php#smart"><?= e(t('Manage', 'Pamahalaan')) ?></a>
        <form method="post" action="settings.php" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_storm"><input type="hidden" name="on" value="0">
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('End it', 'Tapusin')) ?></button></form>
      </span><?php endif; ?></div>
<?php endif;
}

/**
 * Storm mode, for the banner on every page (SMART_SCREENS 5; Rose's asks, 21 Oct 2026). One small read, kept in the session
 * for a minute so no page pays for it twice; Settings clears it the moment storm mode is switched. Null when it is off,
 * has ended, or the read failed: a missing banner must never stop a page.
 */
function storm_state(): ?array
{
    static $memo = false;
    if ($memo !== false) return $memo;
    $c = $_SESSION['ss_storm'] ?? null;
    if (is_array($c) && ($c['at'] ?? 0) > time() - 60) { return $memo = $c['row']; }
    $row = null;
    try {
        $r = db()->select('smart_rules', ['select' => 'storm_mode,storm_until,storm_reason', 'id' => 'eq.1', 'limit' => '1'])[0] ?? null;
        if ($r && !empty($r['storm_mode']) && !empty($r['storm_until']) && strtotime((string) $r['storm_until']) > time()) { $row = $r; }
    } catch (Throwable) { /* no banner this minute */ }
    $_SESSION['ss_storm'] = ['at' => time(), 'row' => $row];
    return $memo = $row;
}

/** The admin's picture on their sidebar card, or their initials. */
function admin_avatar_html(?array $admin): string
{
    $url = $admin['avatar_url'] ?? null;
    $r = rank_of($admin['official_role'] ?? null);
    if (!empty($admin['id'])) { $r = admin_ranks()[(string) $admin['id']] ?? $r; }
    if ($url) return '<img class="p-avatar" data-r="' . e($r) . '" src="' . e(cld_thumb($url, 96, true)) . '" alt="">';
    return '<div class="p-avatar" data-r="' . e($r) . '" aria-hidden="true">' . e(admin_initials((string) ($admin['full_name'] ?? ''))) . '</div>';
}

/**
 * Idle sign-out.
 *
 * This portal lives on a shared desktop in a barangay office and people
 * walk away from it mid-task. Twenty minutes of no keyboard, mouse or
 * scroll and the session ends; at eighteen it asks first, because
 * throwing away half a typed denial reason would be its own problem.
 *
 * The timer is only a convenience — the real expiry is on the session
 * itself, server side. A tab left open with the clock disabled still
 * cannot do anything once the token has lapsed.
 */
function idle_timeout(): void
{
    if (!current_admin()) return;
    ?>
    <div class="p-scrim" id="idle-veil"><div class="p-modal" role="alertdialog" aria-modal="true" aria-labelledby="idle-h" aria-describedby="idle-p">
      <div class="p-m-ico" style="background:var(--p-amber-bg);color:var(--p-amber)"><?= p_icon('i-clock', 26) ?></div>
      <h3 id="idle-h"><?= e(t('Still there?', 'Nandiyan ka pa ba?')) ?></h3>
      <p id="idle-p"><?= e(t("You have been idle for a while. For the barangay's security this session will end in",
                             'Matagal ka nang walang galaw. Para sa seguridad ng barangay, matatapos ang session na ito sa')) ?>
        <b id="idle-left" class="p-num">120</b> <?= e(t('seconds.', 'segundo.')) ?></p>
      <div class="p-actions">
        <button class="p-btn p-btn-ghost" type="button" id="idle-go"><?= e(t('Sign out now', 'Mag-sign out ngayon')) ?></button>
        <button class="p-btn p-btn-primary" type="button" id="idle-stay"><?= e(t('Keep me signed in', 'Manatiling naka-sign in')) ?></button>
      </div>
    </div></div>

    <form method="post" action="logout.php" id="idle-form" hidden>
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
    </form>

    <script>
    (function () {
      var IDLE_MS = 18 * 60 * 1000, GRACE_S = 120;
      var veil = document.getElementById('idle-veil'),
          left = document.getElementById('idle-left'),
          form = document.getElementById('idle-form');
      var idleTimer, graceTimer, remaining;

      function signOut() { form.submit(); }

      function warn() {
        remaining = GRACE_S;
        left.textContent = remaining;
        veil.classList.add('p-on');
        graceTimer = setInterval(function () {
          left.textContent = --remaining;
          if (remaining <= 0) { clearInterval(graceTimer); signOut(); }
        }, 1000);
      }

      function reset() {
        if (veil.classList.contains('p-on')) return;   // the prompt is up; ignore stray events
        clearTimeout(idleTimer);
        idleTimer = setTimeout(warn, IDLE_MS);
      }

      document.getElementById('idle-stay').addEventListener('click', function () {
        clearInterval(graceTimer);
        veil.classList.remove('p-on');
        reset();
      });
      document.getElementById('idle-go').addEventListener('click', signOut);

      ['mousemove', 'keydown', 'scroll', 'click', 'touchstart'].forEach(function (ev) {
        window.addEventListener(ev, reset, { passive: true });
      });
      reset();
    })();
    </script>
    <?php
}

/**
 * Open complaints, for the alternating indicator on Spatial Distribution.
 * Counted once per page render and cached for the request. A failure here
 * must never take a page down, so it swallows and returns zero — the
 * indicator simply does not appear.
 */
/** Two letters for the admin card: first and last word of the name. */
function admin_initials(string $name): string
{
    $w = preg_split('/\s+/', trim(display_name($name))) ?: [];
    $w = array_values(array_filter($w, fn($x) => $x !== ''));
    if (!$w) return 'A';
    $a = mb_substr($w[0], 0, 1);
    $b = count($w) > 1 ? mb_substr($w[count($w) - 1], 0, 1) : '';
    return mb_strtoupper($a . $b);
}

/**
 * The red counts on the sidebar (refined design, 1 Oct 2026): complaints
 * waiting for review, residents waiting for verification, retirement
 * requests waiting for a decision, and open complaints on Spatial. Kept in
 * the session for a minute; any failure just hides a count.
 *
 * @return array<string,int> keyed by nav href
 */
function nav_counts(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $cached = $_SESSION['nav_counts'] ?? null;
    if (is_array($cached) && ($cached['at'] ?? 0) > time() - 60) {
        return $memo = $cached['n'];
    }
    // All four in one batch (speed, 7 Oct 2026): they used to be four calls
    // one after another, the open-complaint count on every single page.
    try {
        $memo = db()->selectMany([
            'cases.php'               => ['reports', ['deleted_at' => 'is.null', 'status' => 'eq.pending_review'], true],
            // the engine's recurring, spike and quiet-case notes are the Notifications page's "Right now" cards, not unread items
            'notifications.php'       => ['notifications', ['user_id' => 'eq.' . (current_admin()['id'] ?? '0'), 'is_read' => 'is.false', 'kind' => 'neq.inbox_mail', 'and' => '(message.not.like.SMART: recurring*,message.not.like.SMART: spike*,message.not.like.SMART:*has had no update for*)'], true],
            'notifications_smart'     => ['notifications', ['user_id' => 'eq.' . (current_admin()['id'] ?? '0'), 'is_read' => 'is.false', 'kind' => 'neq.inbox_mail', 'and' => '(message.like.SMART*,message.not.like.SMART: recurring*,message.not.like.SMART: spike*,message.not.like.SMART:*has had no update for*)'], true],
            'residents.php'           => ['users', ['role' => 'eq.resident', 'verification_status' => 'eq.pending'], true],
            'inbox.php'               => ['inbox_messages', ['recipient' => 'eq.' . (current_admin()['id'] ?? '0'), 'read_at' => 'is.null'], true],
            'administrative-services.php' => ['retirement_requests', ['status' => 'eq.pending'], true],
            'spatial.php'             => ['reports', ['deleted_at' => 'is.null',
                                           'status' => 'in.(pending_review,validated,assigned,in_progress,offline_investigation)'], true],
        ], true);
        $memo = array_map(fn($v) => is_int($v) ? $v : 0, $memo);
    } catch (Throwable) {
        $memo = [];
    }
    $_SESSION['nav_counts'] = ['at' => time(), 'n' => $memo];
    return $memo;
}

function layout_foot(): void
{
    ?>
  </main>
</div>
<?php if ($me = current_admin()): ?>
<script>
// 0087: who is online and which case each admin has open (presence.js).
window.SS_PRESENCE = <?= json_encode([
    'url'      => supabase_url(),
    'key'      => supabase_key(),
    'token'    => access_token(),
    'me'       => ['id' => $me['id'], 'name' => display_name($me['full_name'] ?? '')],
    'ranks'    => admin_ranks(),
    'report'   => $GLOBALS['ss_case']['id'] ?? null,
    'tracking' => $GLOBALS['ss_case']['tracking'] ?? null,
    'page'     => basename($_SERVER['SCRIPT_NAME'] ?? ''),
    'labels'   => [
        'alsoHere' => t('Also here now:', 'Narito rin ngayon:'),
        'you'      => t('You', 'Ikaw'),
        'on'       => t('Has open:', 'Bukas:'),
        'online'   => t('Online', 'Online'),
        'offline'  => t('Offline', 'Offline'),
        'nobody'   => t('Nobody else is online.', 'Walang ibang online.'),
    ],
], JSON_UNESCAPED_UNICODE) ?>;
</script>
<script src="assets/js/presence.js?v=<?= e(asset_version('../js/presence.js')) ?>" defer></script>
<?php endif; ?>
<?php if (current_admin()): ?>
<div class="p-scrim" id="p-m-logout"><div class="p-modal" role="dialog" aria-modal="true" aria-labelledby="p-ml-t">
  <div class="p-m-ico" style="background:var(--p-blue-50);color:var(--p-link)"><?= p_icon('i-out', 26) ?></div>
  <h3 id="p-ml-t"><?= e(t('Log out?', 'Mag-log out?')) ?></h3>
  <p><?= e(t("You'll need to sign in again to manage reports.", 'Kailangan mong mag-sign in muli para mapamahalaan ang mga ulat.')) ?></p>
  <form class="p-actions" method="post" action="logout.php">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
    <button class="p-btn p-btn-ghost" type="button" data-p-close><?= e(t('Stay', 'Manatili')) ?></button>
    <button class="p-btn p-btn-primary" type="submit"><?= e(t('Log out', 'Mag-log out')) ?></button>
  </form>
</div></div>
<?php endif; ?>
<div class="p-scrim" id="p-m-confirm"><div class="p-modal" role="dialog" aria-modal="true" aria-labelledby="p-mc-t">
  <div class="p-m-ico" id="p-mc-ico"></div><h3 id="p-mc-t"></h3><p id="p-mc-p"></p>
  <div class="p-actions"><button class="p-btn p-btn-ghost" type="button" data-p-close><?= e(t('Cancel', 'Kanselahin')) ?></button><button class="p-btn p-btn-primary" type="button" id="p-mc-go"></button></div>
</div></div>
<div class="p-toast" id="p-toast" role="status"></div>
<script src="assets/js/sd-pickers.js?v=<?= e(asset_version('../js/sd-pickers.js')) ?>"></script>
<script>
// Every dropdown and month box on the pills and report bands is the portal's own glass picker; the real controls stay underneath, so forms, auto-submit and the keyboard behave as before.
(function () {
  if (!window.sdPickers) return;
  document.querySelectorAll('.p-pill-select select, .p-band select, .ss-ps select').forEach(function (s) { if (!s.dataset.native) sdPickers.select(s); });
  document.querySelectorAll('.p-pill-select input[type="month"], .p-band input[type="month"]').forEach(function (i) { if (!i.dataset.native) sdPickers.month(i); });
})();
</script>
<?= prefs_script() ?>
<script>
// The three bars shrink the sidebar to its icons and bring it back; the choice is kept in this browser.
(function () {
  var b = document.getElementById('side-edge'), root = document.documentElement;
  if (!b) return;
  function paint() {
    var min = root.getAttribute('data-side') === 'min', t = min ? b.dataset.expand : b.dataset.collapse;
    b.setAttribute('aria-expanded', String(!min)); b.setAttribute('aria-label', t); b.title = t;
  }
  b.addEventListener('click', function () {
    var min = root.getAttribute('data-side') === 'min';
    if (min) root.removeAttribute('data-side'); else root.setAttribute('data-side', 'min');
    try { localStorage.setItem('ss-side', min ? 'max' : 'min'); } catch (e) {}
    paint();
    window.dispatchEvent(new Event('resize'));   // charts and the map redraw to the new width
  });
  paint();
})();
</script>
<?php idle_timeout(); ?>
<?php if (current_admin()): ?>
<script>
// Street labels for complaints that have none yet (0068, geocode.php):
// a few at a time in the background, at most every five minutes per
// tab, and never in the way of the page.
(function () {
  try {
    var last = +sessionStorage.getItem('ss-geocode-at') || 0;
    if (Date.now() - last < 5 * 60 * 1000) return;
    sessionStorage.setItem('ss-geocode-at', String(Date.now()));
  } catch (e) {}
  var rounds = 0;
  (function run() {
    var body = new FormData();
    body.append('csrf', <?= json_encode(csrf_token()) ?>);
    fetch('geocode.php', { method: 'POST', body: body, credentials: 'same-origin' })
      .then(function (r) { return r.json(); })
      .then(function (d) { if (d && d.more && ++rounds < 20) setTimeout(run, 1500); })
      .catch(function () {});
  })();
})();
</script>
<?php endif; ?>
<script>
// One submit per form. A double-click on Accept or Dispatch (or holding
// the A shortcut on case.php) sent two POSTs: the first did the work and
// the second came back with the database's "already reviewed"-style
// error, so the admin landed on a red flash for an action that actually
// succeeded. Buttons are disabled on the next tick, not inside this
// handler, because a disabled submitter is dropped from the form data
// and the server would never see which action was clicked.
(function () {
  document.addEventListener('submit', function (ev) {
    var form = ev.target;
    if (ev.defaultPrevented || String(form.method).toLowerCase() !== 'post') return;
    if (form.dataset.submitting) { ev.preventDefault(); return; }
    form.dataset.submitting = '1';
    setTimeout(function () {
      form.querySelectorAll('button[type="submit"], button:not([type])').forEach(function (b) {
        if (!b.disabled) { b.disabled = true; b.dataset.guarded = '1'; }
      });
    }, 0);
  });
  // Coming back with the browser's Back button can restore the page
  // exactly as it was left, disabled buttons included.
  window.addEventListener('pageshow', function (ev) {
    if (!ev.persisted) return;
    document.querySelectorAll('form[data-submitting]').forEach(function (form) {
      delete form.dataset.submitting;
      form.querySelectorAll('button[data-guarded]').forEach(function (b) {
        b.disabled = false;
        delete b.dataset.guarded;
      });
    });
  });
})();
</script>
<?= turnstile_tags() ?>
</body>
</html>
<?php
}

/** Human labels for the enum values the database stores. */
function status_label(string $s): string
{
    if (lang() === 'fil') {
        $fil = [
            'pending_review'        => 'Naghihintay ng Repaso',
            'validated'             => 'Tinanggap',
            'assigned'              => 'Naka-assign',
            'in_progress'           => 'Isinasagawa',
            'offline_investigation' => 'Imbestigasyon sa Lugar',
            'resolved'              => 'Nalutas',
            'closed'                => 'Sarado',
            'archived'              => 'Naka-archive',
            'rejected'              => 'Tinanggihan',
            'cancelled'             => 'Kinansela',
            // duty_state (0001), in the tanod app's own words
            'on_duty'               => 'Nasa Tungkulin',
            'break'                 => 'Pahinga',
            'lunch'                 => 'Pananghalian',
            'offline'               => 'Naka-offline',
            // verification, roles, dispatch states
            'pending'               => 'Nakabinbin',
            'verified'              => 'Beripikado',
            'resident'              => 'Residente',
            'tanod'                 => 'Tanod',
            'admin'                 => 'Admin',
            'accepted'              => 'Tinanggap',
            'rerouted'              => 'Inilipat',
            'expired'               => 'Nag-expire',
        ];
        if (isset($fil[$s])) return $fil[$s];
    }
    return ucwords(str_replace('_', ' ', $s));
}

/**
 * The outside offices a complaint can be escalated to (0072/0073), and
 * the picker both escalation forms use. "Another office…" reveals a text
 * field (case.php's script, by data-office).
 */
function escalation_offices(): array
{
    // Rose (7 Oct 2026): the five reasons on the Certification of Lack of
    // Jurisdiction, and nothing else.
    return [
        'Lupong Tagapamayapa'        => t('Katarungang Pambarangay (Lupong Tagapamayapa)', 'Katarungang Pambarangay (Lupong Tagapamayapa)'),
        'Philippine National Police' => t('Philippine National Police (PNP) — a criminal offense', 'Philippine National Police (PNP) — krimen'),
        'VAWC Desk'                  => t('VAWC Desk — violence against women and children', 'VAWC Desk — karahasan sa kababaihan at bata'),
        'Office of the Ombudsman'    => t('Grievances against public officers (Ombudsman)', 'Reklamo laban sa pampublikong opisyal (Ombudsman)'),
        'Regular Courts'             => t('Outside the barangay (parties live in different cities)', 'Labas ng barangay (magkaibang lungsod ang tirahan)'),
    ];
}

function office_picker(string $id, ?string $suggested = null): void
{
    $offices = escalation_offices();
    ?>
    <div class="p-cfield">
      <label class="p-flabel" for="<?= e($id) ?>"><?= e(t('Escalate to', 'I-escalate sa')) ?></label>
      <select class="p-input-plain" id="<?= e($id) ?>" name="agency" required data-office>
        <option value=""><?= e(t('Choose an office', 'Pumili ng tanggapan')) ?></option>
        <?php foreach ($offices as $val => $lbl): ?>
          <option value="<?= e($val) ?>" <?= $suggested === $val ? 'selected' : '' ?>><?= e($lbl) ?></option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="p-cfield" data-office-other hidden>
      <label class="p-flabel" for="<?= e($id) ?>-other"><?= e(t('Name of the office', 'Pangalan ng tanggapan')) ?></label>
      <input class="p-input-plain" type="text" id="<?= e($id) ?>-other" name="agency_other" maxlength="120">
    </div>
    <?php
}

/**
 * An open complaint whose admin-set target date has passed (0071/0072).
 * Escalation is no longer automatic; this is what the screens show.
 */
function report_is_overdue(array $r): bool
{
    return !empty($r['due_at'])
        && strtotime((string) $r['due_at']) < time()
        && !in_array($r['status'] ?? '', ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true);
}

/** status_label() for every value, for the pages' live scripts to share. */
function status_labels(): array
{
    $out = [];
    foreach (['pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation',
              'resolved', 'closed', 'archived', 'rejected', 'cancelled', 'on_duty', 'break',
              'lunch', 'offline', 'pending', 'verified', 'resident', 'tanod', 'admin',
              'accepted', 'rerouted', 'expired'] as $s) {
        $out[$s] = status_label($s);
    }
    return $out;
}

/**
 * A sensitive case's own status (Rose, 21 Oct 2026). 0130 marks VAWC and similar complaints sensitive; the mark sits beside
 * the case's progress (Under review, In progress, Resolved…) rather than replacing it, because a sensitive case still
 * goes through every step. Shown wherever the portal shows a case's status. Never shown to the resident.
 */
function sensitive_badge(?array $r): string
{
    if (empty($r['is_sensitive'])) { return ''; }
    return '<span class="p-badge p-b-sensitive" title="' . e(t('Sensitive case: elevate it, and send a designated woman responder if a tanod is needed', 'Sensitibong kaso: i-elevate, at magpadala ng itinalagang babaeng responder kung kailangan ng tanod')) . '">'
         . '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3 5 6v5.5c0 4.3 2.9 7.7 7 9.5 4.1-1.8 7-5.2 7-9.5V6z"/></svg>'
         . e(t('Sensitive', 'Sensitibo')) . '</span>';
}

function status_class(string $s): string
{
    // The preview's badge colours: p-b-<this>.
    return match ($s) {
        'pending_review'        => 'pending',
        'validated', 'assigned',
        'in_progress',
        'offline_investigation' => 'progress',
        'resolved'              => 'done',
        'closed', 'archived'    => 'grey',
        'rejected'              => 'denied',
        default                 => 'pending',
    };
}

/**
 * The complaint categories (0146: a table a super admin edits in Settings > Complaint types), read once per request:
 * key => [en, fil, colour, icon, active]. The list below is only the fallback when the table cannot be read.
 */
function categories_all(): array
{
    static $memo = null;
    if ($memo !== null) return $memo;
    $memo = [];
    try {
        if (access_token() !== null) {
            foreach ((array) db()->select('complaint_categories', ['select' => 'key,label_en,label_fil,colour,icon,active,sort', 'order' => 'sort.asc,key.asc']) as $c) {
                $memo[(string) $c['key']] = ['en' => (string) $c['label_en'], 'fil' => (string) $c['label_fil'], 'colour' => (string) $c['colour'],
                                             'icon' => (string) $c['icon'], 'active' => !empty($c['active'])];
            }
        }
    } catch (Throwable) {}
    if (!$memo) {
        foreach ([
            'street_obstruction'           => ['Street Obstruction', 'Sagabal sa Kalsada', '#F93535'],
            'public_safety_infrastructure' => ['Public Safety and Infrastructure', 'Kaligtasan at Imprastraktura', '#356CF9'],
            'environmental_waste_hazard'   => ['Environmental and Waste Hazards', 'Kapaligiran at Basura', '#F9AB35'],
            'animal_welfare'               => ['Animal Welfare', 'Kapakanan ng Hayop', '#34C759'],
            'traffic_violation'            => ['Traffic Violation', 'Paglabag sa Trapiko', '#8E9ABB'],
            'barangay_service'             => ['Barangay Service', 'Serbisyo ng Barangay', '#422F8A'],
            'peace_order_nuisance'         => ['Peace, Order, & Nuisance', 'Kapayapaan, Kaayusan at Istorbo', '#E0609A'],
            'other'                        => ['Others', 'Iba pa', '#0F9D9A'],
        ] as $k => [$en, $fil, $col]) {
            $memo[$k] = ['en' => $en, 'fil' => $fil, 'colour' => $col, 'icon' => $k, 'active' => true];
        }
    }
    return $memo;
}

/** The category keys, in the barangay's order; with $active, only the ones residents can still pick. */
function category_keys(bool $active = false): array
{
    return array_keys(array_filter(categories_all(), fn (array $c): bool => !$active || $c['active']));
}

/** key => [English, Tagalog], the shape the Settings forms use. */
function category_pairs(bool $active = false): array
{
    $out = [];
    foreach (categories_all() as $k => $c) { if (!$active || $c['active']) $out[$k] = [$c['en'], $c['fil']]; }
    return $out;
}

/** One colour per category, shared by the dashboard's charts and the spatial map's pins (Rose, 2 Oct 2026). */
function category_colours(): array
{
    return array_map(fn (array $c): string => $c['colour'], categories_all());
}

/** The barangay's own names for the categories (its Complaint Summary form), in the portal's language. */
function category_label(string $c): string
{
    $x = categories_all()[$c] ?? null;
    return $x ? t($x['en'], $x['fil']) : ucwords(str_replace('_', ' ', $c));
}

function short_date(?string $iso): string
{
    if (!$iso) return '';
    try {
        return (new DateTimeImmutable($iso))
            ->setTimezone(new DateTimeZone('Asia/Manila'))
            ->format('m/d/y');
    } catch (Exception) {
        return '';
    }
}

/** "May 06, 2026 • 10:45 AM", the format the Figma uses throughout. */
function long_datetime(?string $iso): string
{
    if (!$iso) return '';
    try {
        return (new DateTimeImmutable($iso))
            ->setTimezone(new DateTimeZone('Asia/Manila'))
            ->format('M d, Y \• g:i A');
    } catch (Exception) {
        return '';
    }
}

/** Value for an <input type="datetime-local">, which has no timezone. */
function local_input_value(?string $iso): string
{
    if (!$iso) return '';
    try {
        return (new DateTimeImmutable($iso))
            ->setTimezone(new DateTimeZone('Asia/Manila'))
            ->format('Y-m-d\TH:i');
    } catch (Exception) {
        return '';
    }
}

function byte_size(int $bytes): string
{
    return $bytes >= 1048576
        ? round($bytes / 1048576, 1) . ' MB'
        : max(1, (int) round($bytes / 1024)) . ' KB';
}

/** Metres from PostGIS, rounded to something a person would say out loud. */
function distance_label(float $metres): string
{
    return $metres < 950
        ? round($metres / 10) * 10 . ' m'
        : round($metres / 1000, 1) . ' km';
}

function coord_label(float $lat, float $lng): string
{
    return number_format($lat, 5) . ', ' . number_format($lng, 5);
}

/**
 * A trail entry reads as a sentence, not as an enum pair. A row where the
 * status did not move is an annotation — a note, a deadline change —
 * rather than a transition, so it should not claim one happened.
 */
function timeline_title(array $log): string
{
    $old    = $log['old_status'] ?? null;
    $new    = $log['new_status'] ?? '';
    $remark = (string) ($log['remark'] ?? '');

    // A null old_status used to mean "this is the first entry", and the
    // filing log is indeed written that way. But the SLA and dispatch
    // sweeps in 0002 insert (report_id, new_status, remark, is_system)
    // and leave old_status null too — so a breach three days into a case
    // was being titled "Complaint Filed", above the entries it followed.
    //
    // is_system separates them. The barangay never files a complaint;
    // residents do, through file_report(), which records the actor. So a
    // system row with no previous status is a note about the case, not
    // the start of it.
    if ($old === null && empty($log['is_system'])) {
        return t('Complaint Filed', 'Naisampa ang Sumbong');
    }

    // Rose's feedback (Sep 2026): name what actually happened, in plain
    // terms, rather than the generic fallback below — her own example was
    // "Resolution Deadline Missed" for exactly the SLA-breach row. These
    // are the recurring system annotations (old_status often equals
    // new_status for these, which is what used to collapse them all into
    // "Case updated"); the remark itself still renders underneath for the
    // full detail, so the title only needs to name the kind of event, not
    // repeat it.
    if (str_starts_with($remark, 'SLA breach')) {
        return t('Resolution Deadline Missed', 'Lumampas sa Takdang Paglutas');
    }
    if (str_starts_with($remark, 'Resident appealed the rejection')) {
        return t('Appeal Requested', 'Humiling ng Apela');
    }
    if (str_starts_with($remark, 'Appeal granted')) {
        return t('Appeal Granted', 'Pinagbigyan ang Apela');
    }
    if (str_starts_with($remark, 'Rerouted:')) {
        return t('Dispatch Rerouted', 'Inilipat ang Dispatch');
    }
    if (str_starts_with($remark, 'Reopened:')) {
        return t('Complaint Reopened', 'Muling Binuksan ang Sumbong');
    }
    if (str_starts_with($remark, 'Outside Barangay 183')) {
        return t('Referred Outside Barangay', 'Ini-refer sa Labas ng Barangay');
    }
    if (str_starts_with($remark, 'No tanod')) {
        return t('No Tanod Available', 'Walang Available na Tanod');
    }
    if (str_starts_with($remark, 'Auto-dispatched')) {
        return t('Auto-Dispatched', 'Awtomatikong Na-dispatch');
    }
    if (str_starts_with($remark, 'Re-dispatching')) {
        return t('Re-Dispatch Attempted', 'Sinubukang I-dispatch Muli');
    }
    if (str_starts_with($remark, 'Automatic dispatch gave up')) {
        return t('Automatic Dispatch Exhausted', 'Hindi Na-dispatch nang Awtomatiko');
    }
    if (str_starts_with($remark, 'Resolution target set to')
        || str_starts_with($remark, 'Expected to be resolved by')) {   // 0071's wording
        return t('Resolution Target Set', 'Naitakda ang Target na Paglutas');
    }
    if (str_starts_with($remark, 'Resolution target moved')
        || str_starts_with($remark, 'Expected resolution moved')) {
        return t('Resolution Target Moved', 'Inilipat ang Target na Paglutas');
    }
    // The dispatch window's steps (0069) and the admin's reroute (0070).
    if (str_starts_with($remark, 'Tanod is on the way')) {
        return t('Tanod On the Way', 'Papunta na ang Tanod');
    }
    if (str_starts_with($remark, 'Tanod has arrived')) {
        return t('Tanod Arrived', 'Nakarating ang Tanod');
    }
    // The resident's side of the trail (0057, 0065).
    if (str_starts_with($remark, 'Resident requested reopening')) {
        return t('Reopen Requested', 'Hiniling na Buksan Muli');
    }
    if (str_starts_with($remark, 'More details requested')) {
        return t('More Details Requested', 'Humiling ng Karagdagang Detalye');
    }
    if (str_starts_with($remark, 'Resident sent more details')) {
        return t('More Details Sent', 'Nagpadala ng Karagdagang Detalye');
    }
    if (str_starts_with($remark, 'Appeal requested') || str_starts_with($remark, 'Resident appealed')) {
        return t('Appeal Requested', 'Humiling ng Apela');
    }
    // 0072: the admin's referral and the resident's follow-up.
    if (str_starts_with($remark, 'Referred to ') || str_starts_with($remark, 'Escalated to ')) {
        return t('Escalated to an Outside Office', 'In-escalate sa Ibang Tanggapan');
    }
    // 0073: resolution approval, escalation requests, manual status.
    if (str_starts_with($remark, 'Resolution report submitted')) {
        return t('Resolution Submitted for Approval', 'Isinumite ang Resolusyon para Aprubahan');
    }
    if (str_starts_with($remark, 'Resolution returned')) {
        return t('Resolution Returned to Tanod', 'Ibinalik sa Tanod ang Resolusyon');
    }
    if (str_starts_with($remark, 'Escalation request denied')) {
        return t('Escalation Request Denied', 'Tinanggihan ang Hiling na I-escalate');
    }
    if (str_starts_with($remark, 'Status set to')) {
        return t('Status Updated', 'Na-update ang Katayuan');
    }
    if (str_starts_with($remark, 'The resident followed up')) {
        return t('Resident Followed Up', 'Nag-follow Up ang Residente');
    }
    if (str_starts_with($remark, 'Rerouted by the barangay')) {
        return t('Rerouted by the Barangay', 'Inilipat ng Barangay');
    }

    if ($old === null || $old === $new) {
        return t('Case Update', 'Update sa Kaso');
    }
    return match ($new) {
        'validated'  => t('Complaint Accepted', 'Tinanggap ang Sumbong'),
        'rejected'   => t('Complaint Denied', 'Tinanggihan ang Sumbong'),
        'assigned'   => t('Tanod Assigned', 'Na-assign ang Tanod'),
        'in_progress'=> t('Response Underway', 'Tumutugon na'),
        'resolved'   => t('Marked Resolved', 'Minarkahang Nalutas'),
        'closed'     => t('Case Closed', 'Isinara ang Kaso'),
        default      => status_label((string) $new),
    };
}

/**
 * What the operator is allowed to see when something fails.
 *
 * Our own functions raise messages written for barangay staff — "A reason
 * is required when denying a complaint" — and those should be shown. What
 * must not reach the screen is PostgREST and PostgreSQL internals:
 * constraint names, function signatures, column lists and schema
 * structure, which tell an attacker how the system is put together.
 *
 * Anything that looks like machinery is replaced with a reference the
 * barangay can quote to whoever maintains the system.
 */
function safe_error(Throwable $e): string
{
    $msg = $e->getMessage();

    $machinery = ['violates', 'constraint', 'relation ', 'column ', 'syntax error',
                  'function ', 'permission denied', 'duplicate key', 'PGRST',
                  'null value', 'invalid input', 'does not exist', 'schema '];

    foreach ($machinery as $needle) {
        if (stripos($msg, $needle) !== false) {
            error_log('SmartSumbong: ' . $msg);
            return t('That action could not be completed. Reference: ', 'Hindi natapos ang aksyong iyon. Reference: ')
                 . substr(hash('sha256', $msg), 0, 8)
                 . t(' — give this to whoever maintains the system.', ' — ibigay ito sa nangangalaga ng system.');
        }
    }
    return $msg;
}

function relative_time(?string $iso): string
{
    if (!$iso) return '';
    try {
        $then = new DateTimeImmutable($iso);
    } catch (Exception) {
        return '';
    }
    $mins = (int) round((time() - $then->getTimestamp()) / 60);
    if ($mins < 1)    return t('Just now', 'Ngayon lang');
    if ($mins < 60)   return t("{$mins} min ago", "{$mins} minutong nakalipas");
    if ($mins < 1440) return t(floor($mins / 60) . ' hr ago', floor($mins / 60) . ' oras na nakalipas');
    return $then->setTimezone(new DateTimeZone('Asia/Manila'))->format(t('M j \a\t g:i A', 'M j, g:i A'));
}

/** 0087: the colour an admin's initials sit on, stable per account. */
function admin_colour(string $id): string
{
    // The same hash as presence.js, so a face is the same colour everywhere.
    $palette = ['#C2185B', '#00308F', '#2E7D32', '#6A1B9A', '#E65100', '#00838F', '#AD1457', '#283593'];
    $h = 0;
    foreach (str_split($id) as $c) { $h = ($h * 31 + ord($c)) & 0xFFFFFFFF; }
    return $palette[$h % count($palette)];
}

/**
 * Every administrator's rung (staff, kagawad, chair), id => rung, for the ring round a face. One small read,
 * kept in the session for five minutes so it costs nothing on most pages; a failure only means no rings.
 */
function admin_ranks(): array
{
    static $map = null;
    if ($map !== null) { return $map; }
    session_start_once();
    $c = $_SESSION['ss_ranks'] ?? null;
    if (is_array($c) && time() - (int) ($c['t'] ?? 0) < 300) { return $map = (array) $c['m']; }
    $map = [];
    try {
        foreach (db()->select('users', ['select' => 'id,official_role', 'role' => 'eq.admin']) as $u) { $map[(string) $u['id']] = rank_of($u['official_role'] ?? null); }
        $_SESSION['ss_ranks'] = ['t' => time(), 'm' => $map];
    } catch (Throwable $e) { /* no rings this time */ }
    return $map;
}

function admin_chip(string $id, string $name, int $size = 24): string
{
    $r = admin_ranks()[$id] ?? null;
    return '<span class="ss-av"' . ($r ? ' data-r="' . e($r) . '"' : '') . ' style="width:' . $size . 'px;height:' . $size . 'px;font-size:' . max(9, intdiv($size, 3)) . 'px;background:'
        . admin_colour($id) . '" title="' . e(display_name($name)) . '">' . e(admin_initials($name)) . '</span>';
}

/** 0087: the Handler cell of the case list. */
function handler_cell(array $r, string $me): string
{
    if (empty($r['handler_id'])) {
        return '<span class="p-sub">' . e(t('Nobody yet', 'Wala pa')) . '</span>';
    }
    $name = (string) ($r['handler']['full_name'] ?? '');
    return '<span class="ss-who">' . admin_chip((string) $r['handler_id'], $name) . e($r['handler_id'] === $me ? t('You', 'Ikaw') : $name) . '</span>';
}

/** "Besarra, Rose" -> "Rose Besarra" (0088); anything else unchanged. */
/**
 * A smaller copy of a Cloudinary photo for showing it small (speed, 7 Oct
 * 2026): $w wide, or a $w square cropped to the face for avatars. Links
 * still point at the original; anything that is not a Cloudinary image is
 * returned as is.
 */
function cld_thumb(?string $url, int $w, bool $square = false): string
{
    $url = (string) $url;
    $t = ($square ? "c_fill,g_face,w_$w,h_$w" : "c_limit,w_$w") . ',q_auto,f_auto';
    if (str_contains($url, '/image/authenticated/')) return cld_private_url($url, $t);
    if (!preg_match('#^https://res\.cloudinary\.com/[^/]+/image/upload/#', $url)) return $url;
    return preg_replace('#/image/upload/#', "/image/upload/$t/", $url, 1);
}

/**
 * A link that opens a private identity photo (0117): Cloudinary's signed
 * delivery URL, the SHA-256 of the transformation and asset path with the API
 * secret. The stored address alone opens nothing. Without the secret in
 * the environment the stored address comes back unchanged (and will not
 * load), which is the safe way to fail.
 */
function cld_private_url(string $url, string $transformation = ''): string
{
    if (!preg_match('#^(https://res\.cloudinary\.com/[^/]+/image/authenticated/)(v[0-9]+)/(.+)$#', $url, $m)) return $url;
    $secret = env('CLOUDINARY_API_SECRET', '');
    if ($secret === '') return $url;
    $toSign = ($transformation !== '' ? $transformation . '/' : '') . $m[3];
    $sig = substr(strtr(base64_encode(hash('sha256', $toSign . $secret, true)), '+/', '-_'), 0, 8);
    return $m[1] . 's--' . $sig . '--/' . ($transformation !== '' ? $transformation . '/' : '') . $m[2] . '/' . $m[3];
}

/**
 * How a name is written (Ace, 7 Oct 2026), same in the app:
 *   formal — records, profiles, lists, documents: "Lediac, Ace" (as stored) — formal_name()
 *   casual — greetings, bylines, chips, sentences: "Ace Lediac" — display_name()
 */
function formal_name(?string $name): string
{
    return trim((string) $name);
}

/** formal_name(), or $fallback when there is no name. */
function formal_or(?string $name, string $fallback): string
{
    $n = formal_name($name);
    return $n !== '' ? $n : $fallback;
}

/** display_name(), or $fallback when there is no name. */
function name_or(?string $name, string $fallback): string
{
    $n = display_name($name);
    return $n !== '' ? $n : $fallback;
}

function display_name(?string $name): string
{
    $name = (string) $name;
    $c = strpos($name, ',');
    return $c > 0 ? trim(substr($name, $c + 1)) . ' ' . trim(substr($name, 0, $c)) : $name;
}
