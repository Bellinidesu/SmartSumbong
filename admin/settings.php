<?php
/**
 * Settings (3 Oct 2026): System status and Plan and usage.
 *
 * System status checks every service the portal depends on and says in
 * plain words what is wrong and what it means for the barangay. Supabase,
 * Cloudinary and the push function are checked from this server (?check=
 * server); map tiles, address lookup, rain data, live updates and the
 * Project NOAH file are checked from the admin's own browser, because
 * that is where they load.
 *
 * Plan and usage shows how close the barangay is to each plan's limits:
 * Supabase's database size, file storage and active users come from the
 * database itself (system_usage(), 0078); Cloudinary's credits need its
 * API key and secret in the server's environment; the rest are the
 * providers' published limits. No key or password ever reaches the page.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();

// 0084 (Rose): add an administrator, or issue one a new temporary
// password. The password is shown once, here, and never stored by the portal.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['add_admin', 'reset_admin'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            // Rose (6 Oct 2026): nobody but the new admin sees a password.
            // The account is made with a random one nobody is shown, and
            // the admin's own email gets a link to choose theirs.
            $who = trim((string) ($_POST['email'] ?? ''));
            if ($_POST['action'] === 'add_admin') {
                $db->rpc('create_admin_account', [
                    'p_email'     => $who,
                    'p_full_name' => trim((string) ($_POST['last_name'] ?? '')) . ', ' . trim((string) ($_POST['first_name'] ?? '')),
                    'p_mobile'    => trim((string) ($_POST['mobile'] ?? '')),
                ]);
            }
            $secure = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
                   || strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
            Supabase::recover($who, ($secure ? 'https://' : 'http://') . $_SERVER['HTTP_HOST']
                . dirname($_SERVER['SCRIPT_NAME']) . '/reset-password.php');
            $_SESSION['st_flash'] = ['level' => 'ok', 'who' => $who, 'new' => $_POST['action'] === 'add_admin'];
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: settings.php#admins');
    exit;
}

// The plan each service is on. These are the free tiers the barangay
// started on; change them here if an account is upgraded.
const PLAN_TIERS = ['supabase' => 'Free', 'cloudinary' => 'Free', 'render' => 'Free'];

// Where each service runs, as looked up on 3 Oct 2026: Supabase from the
// project's settings (ap-south-1), the others from where their addresses
// answer. Render's region is set in its dashboard and not visible outside.
const SERVICE_PLACES = [
    'db'    => ['IN',  'Mumbai, India'],
    'auth'  => ['IN',  'Mumbai, India'],
    'live'  => ['IN',  'Mumbai, India'],
    'media' => ['CDN', 'Nearest Cloudflare edge'],
    'push'  => ['CDN', 'Nearest Google edge'],
    'tiles' => ['CDN', 'Nearest Cloudflare edge'],
    'geo'   => ['PH',  'Manila edge (Fastly)'],
    'rain'  => ['DE',  'Falkenstein, Germany'],
    'noah'  => ['—',   'With the portal (Render)'],
];

/** One timed HTTP request: any answer below 500 means the service is reachable. */
function probe(string $url, array $headers = [], string $method = 'GET'): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_NOBODY         => $method === 'HEAD',
        CURLOPT_CUSTOMREQUEST  => $method === 'HEAD' ? null : $method,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_TIMEOUT        => 8,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_FOLLOWLOCATION => false,
    ]);
    $t0 = microtime(true);
    curl_exec($ch);
    $ms   = (int) round((microtime(true) - $t0) * 1000);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return ['ok' => $code > 0 && $code < 500, 'ms' => $code > 0 ? $ms : null, 'code' => $code];
}

if (($_GET['check'] ?? '') === 'server') {
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    $out = [];
    // Database: a real one-row read with this admin's session.
    $t0 = microtime(true);
    try { $db->select('reports', ['select' => 'id', 'limit' => '1']); $out['db'] = ['ok' => true, 'ms' => (int) round((microtime(true) - $t0) * 1000)]; }
    catch (Throwable $e) { $out['db'] = ['ok' => false, 'ms' => null]; }
    $key = ['apikey: ' . supabase_key()];
    $out['auth']  = probe(supabase_url() . '/auth/v1/health', $key);
    $out['push']  = probe(supabase_url() . '/functions/v1/send-dispatch-push', $key, 'OPTIONS');
    $cloud = env('CLOUDINARY_CLOUD_NAME', '');
    $out['media'] = $cloud !== '' ? probe('https://res.cloudinary.com/' . rawurlencode($cloud) . '/image/upload/v1/ping', [], 'HEAD') : ['ok' => false, 'ms' => null, 'unset' => true];
    $fcm = probe('https://fcm.googleapis.com/', [], 'HEAD');
    if ($out['push']['ok'] && !$fcm['ok']) { $out['push'] = ['ok' => false, 'ms' => null]; }
    echo json_encode($out);
    exit;
}

if (($_GET['usage'] ?? '') === '1') {
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    $tz    = new DateTimeZone('Asia/Manila');
    $month = (new DateTimeImmutable('first day of this month', $tz))->setTime(0, 0)->format(DateTimeInterface::ATOM);
    $out = ['plans' => PLAN_TIERS];
    try { $out['supabase'] = $db->rpc('system_usage'); } catch (Throwable $e) { $out['supabase'] = null; }
    try {
        $media = $db->select('report_media', ['select' => 'bytes', 'limit' => '20000']);
        $out['photos'] = ['files' => count($media), 'bytes' => array_sum(array_map(fn($m) => (int) $m['bytes'], $media))];
    } catch (Throwable $e) { $out['photos'] = null; }
    try { $out['alerts'] = $db->count('dispatches', ['assigned_at' => 'gte.' . $month]); } catch (Throwable $e) { $out['alerts'] = null; }
    // Cloudinary's own usage figures, only when its API key and secret are set.
    $cloud = env('CLOUDINARY_CLOUD_NAME', ''); $ck = env('CLOUDINARY_API_KEY', ''); $cs = env('CLOUDINARY_API_SECRET', '');
    $out['cloudinary'] = null;
    if ($cloud !== '' && $ck !== '' && $cs !== '') {
        $ch = curl_init('https://api.cloudinary.com/v1_1/' . rawurlencode($cloud) . '/usage');
        curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_USERPWD => $ck . ':' . $cs, CURLOPT_TIMEOUT => 8]);
        $body = curl_exec($ch); $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE); curl_close($ch);
        if ($code === 200 && ($u = json_decode((string) $body, true))) {
            $out['cloudinary'] = ['plan' => $u['plan'] ?? null, 'credits_used' => $u['credits']['usage'] ?? null, 'credits_limit' => $u['credits']['limit'] ?? null,
                                  'storage' => $u['storage']['usage'] ?? null, 'bandwidth' => $u['bandwidth']['usage'] ?? null];
        }
    }
    echo json_encode($out);
    exit;
}

layout_head(t('Settings', 'Mga Setting'), 'settings.php');
?>
<div class="p-topbar"><h1><?= e(t('Settings', 'Mga Setting')) ?></h1><span class="p-updated" id="st-checked"></span><span style="flex:1"></span>
  <button class="p-btn p-btn-primary p-btn-sm" id="st-check" type="button"><?= e(t('Check again', 'Suriin muli')) ?></button></div>

<div class="p-seg-mini st-tabs" role="tablist" aria-label="<?= e(t('Settings sections', 'Mga bahagi ng setting')) ?>">
  <button type="button" class="p-on" role="tab" data-st="status"><?= e(t('System status', 'Kalagayan ng sistema')) ?></button>
  <button type="button" role="tab" data-st="usage"><?= e(t('Plan and usage', 'Plano at paggamit')) ?></button>
  <button type="button" role="tab" data-st="admins"><?= e(t('Administrators', 'Mga Administrator')) ?></button>
</div>

<?php
// Rose (5 Oct 2026): every administrator, and whether they still hold a
// temporary password. Adding one from here comes with the account service.
$stFlash = $_SESSION['st_flash'] ?? null;
unset($_SESSION['st_flash']);
$admins = [];
try {
    $admins = $db->select('users', [
        'select' => 'id,full_name,email,must_change_password,is_suspended,created_at',
        'role'   => 'eq.admin',
        'order'  => 'created_at.asc',
    ]);
} catch (SupabaseError $e) { $admins = []; }
?>
<section class="st-pane" data-pane="admins" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'ok'): ?>
    <div class="p-flash p-flash--ok" role="status">
      <?= e(!empty($stFlash['new']) ? t('Account created. A link to set a password was emailed to', 'Nagawa ang account. Naipadala ang link para magtakda ng password sa') : t('A link to set a new password was emailed to', 'Naipadala ang link para magtakda ng bagong password sa')) ?>
      <b><?= e($stFlash['who']) ?></b>. <?= e(t('Only they can see it.', 'Sila lang ang makakakita nito.')) ?>
    </div>
  <?php elseif ($stFlash): ?>
    <div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div>
  <?php endif; ?>
  <div class="p-card p-table-card"><div class="p-tscroll"><table class="p-t">
    <thead><tr><th><?= e(t('Name', 'Pangalan')) ?></th><th><?= e(t('Email', 'Email')) ?></th><th><?= e(t('Account', 'Account')) ?></th><th><?= e(t('Online now', 'Online ngayon')) ?></th><th></th></tr></thead>
    <tbody>
    <?php foreach ($admins as $a): ?>
      <tr>
        <td><span class="ss-who"><?= admin_chip($a['id'], (string) $a['full_name'], 28) ?><?= e(formal_name($a['full_name'])) ?></span><?= $a['id'] === $admin['id'] ? ' <small>(' . e(t('you', 'ikaw')) . ')</small>' : '' ?></td>
        <td><?= e((string) ($a['email'] ?? '')) ?></td>
        <td><?php if (!empty($a['is_suspended'])): ?><span class="p-chip"><?= e(t('Suspended', 'Suspendido')) ?></span><?php elseif (!empty($a['must_change_password'])): ?><span class="p-chip"><?= e(t('Must change password', 'Kailangang palitan ang password')) ?></span><?php else: ?><span class="p-chip"><?= e(t('Active', 'Aktibo')) ?></span><?php endif; ?></td>
        <td class="ss-online" data-admin="<?= e($a['id']) ?>"><span class="ss-dot"></span><?= e(t('Offline', 'Offline')) ?></td>
        <td class="p-right"><?php if ($a['id'] !== $admin['id']): ?>
          <form method="post" data-captcha data-native-confirm="<?= e(t('Email this administrator a link to set a new password?', 'I-email sa administrator na ito ang link para magtakda ng bagong password?')) ?>">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="reset_admin">
            <input type="hidden" name="user" value="<?= e($a['id']) ?>">
            <input type="hidden" name="email" value="<?= e((string) ($a['email'] ?? '')) ?>">
            <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Email a password link', 'I-email ang link ng password')) ?></button>
          </form>
        <?php endif; ?></td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table></div></div>
  <div class="p-card p-card-pad ss-addadmin">
    <p class="p-eyebrow"><?= e(t('Add an administrator', 'Magdagdag ng administrator')) ?></p>
    <p class="p-hint"><?= e(t('The new administrator gets an email with a link to choose their own password. Nobody else ever sees it. Use their real email address.', 'Makakatanggap ang bagong administrator ng email na may link para pumili ng sariling password. Walang ibang makakakita nito. Gamitin ang tunay nilang email.')) ?></p>
    <form method="post" class="ss-form" data-captcha data-native-confirm="<?= e(t('Add this administrator? They get an email to set their password.', 'Idagdag ang administrator na ito? Makakatanggap sila ng email para sa password.')) ?>">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
      <input type="hidden" name="action" value="add_admin">
      <input class="p-input-plain" name="first_name" required maxlength="60" placeholder="<?= e(t('First name', 'Pangalan')) ?>" aria-label="<?= e(t('First name', 'Pangalan')) ?>">
      <input class="p-input-plain" name="last_name" required maxlength="60" placeholder="<?= e(t('Last name', 'Apelyido')) ?>" aria-label="<?= e(t('Last name', 'Apelyido')) ?>">
      <input class="p-input-plain" name="email" type="email" required maxlength="160" placeholder="<?= e(t('Email address', 'Email address')) ?>">
      <input class="p-input-plain" name="mobile" required pattern="09[0-9]{9}" placeholder="09XXXXXXXXX">
      <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Create account', 'Gumawa ng account')) ?></button>
    </form>
  </div>
</section>

<?php
// 0096 (industry pass 5): the database pings the portal every 10 minutes
// and keeps score.
$up = null;
try { $up = $db->rpc('portal_uptime_summary'); } catch (SupabaseError) {}
$errs = null;
try { $errs = $db->select('portal_errors', ['select' => 'source,page,message,count,last_seen', 'order' => 'last_seen.desc', 'limit' => '5']); } catch (SupabaseError) {}
// 0119: what the hourly health check found and has not seen clear yet.
$alerts = [];
try { $alerts = $db->select('system_alerts', ['select' => 'key,message,raised_at', 'cleared_at' => 'is.null', 'order' => 'raised_at.desc']); } catch (SupabaseError) {}
$upPct = fn(int $ok, int $n) => $n > 0 ? rtrim(rtrim(number_format($ok / $n * 100, 2), '0'), '.') . '%' : '—';
?>
<section class="st-pane" data-pane="status">
  <div class="st-banner" id="st-banner"></div>
  <?php if ($alerts): ?>
  <div class="p-card p-card-pad st-alerts" role="alert">
    <p class="p-eyebrow"><?= e(t('Needs attention', 'Kailangang tingnan')) ?></p>
    <ul class="st-err-list">
      <?php foreach ($alerts as $al): ?>
        <li><span class="p-badge p-b-denied"><?= e(t('Open', 'Bukas')) ?></span>
          <div><b><?= e(ucfirst((string) $al['message'])) ?></b><small><?= e(t('Since ', 'Mula ') . relative_time($al['raised_at'])) ?></small></div></li>
      <?php endforeach; ?>
    </ul>
    <p class="st-note"><?= e(t('Checked every hour. An alert closes on its own once the problem is gone; see docs/INCIDENTS.md for what to do.', 'Sinusuri bawat oras. Kusang nagsasara ang alerto kapag nawala na ang problema; tingnan ang docs/INCIDENTS.md.')) ?></p>
  </div>
  <?php endif; ?>
  <?php if (is_array($up)): ?>
  <div class="p-card p-card-pad st-uptime">
    <p class="p-eyebrow"><?= e(t('Portal uptime', 'Uptime ng portal')) ?></p>
    <div class="st-uptime-tiles">
      <div class="st-uptime-tile"><b><?= e($upPct((int) $up['day_ok'], (int) $up['day_checks'])) ?></b><span><?= e(sprintf(t('Last 24 hours · %d checks', 'Nakaraang 24 oras · %d pagsusuri'), (int) $up['day_checks'])) ?></span></div>
      <div class="st-uptime-tile"><b><?= e($upPct((int) $up['week_ok'], (int) $up['week_checks'])) ?></b><span><?= e(sprintf(t('Last 7 days · %d checks', 'Nakaraang 7 araw · %d pagsusuri'), (int) $up['week_checks'])) ?></span></div>
      <div class="st-uptime-tile<?= $up['last_ok'] === false ? ' st-down' : '' ?>"><b><?= e($up['last_at'] ? ($up['last_ok'] ? t('Answering', 'Sumasagot') : t('Not answering', 'Hindi sumasagot')) : '—') ?></b><span><?= e($up['last_at'] ? t('Last check ', 'Huling pagsusuri ') . relative_time($up['last_at']) : t('No checks yet', 'Wala pang pagsusuri')) ?></span></div>
    </div>
    <p class="st-note"><?= e(t('The database asks the portal for a tiny page every 10 minutes, which also keeps the free server from going to sleep.', 'Tuwing 10 minuto, humihingi ang database ng maliit na pahina sa portal; pinipigilan din nito ang pagtulog ng libreng server.')) ?></p>
  </div>
  <?php endif; ?>
  <?php if (is_array($errs)): ?>
  <div class="p-card p-card-pad st-errors">
    <p class="p-eyebrow"><?= e(t('Recent errors', 'Mga kamakailang error')) ?></p>
    <?php if (!$errs): ?>
      <p class="p-none-line"><?= e(t('No errors recorded. Anything that goes wrong on the portal, on the server, in a browser or in an Edge Function, is listed here.', 'Walang naitalang error. Dito lalabas ang anumang mali sa portal, sa server man o sa browser.')) ?></p>
    <?php else: ?>
      <ul class="st-err-list">
        <?php foreach ($errs as $er): ?>
          <li><span class="p-badge <?= $er['source'] === 'browser' ? 'p-b-progress' : 'p-b-denied' ?>"><?= e(match ($er['source']) { 'server' => t('Server', 'Server'), 'function' => t('Function', 'Function'), default => t('Browser', 'Browser') }) ?></span>
            <div><b><?= e($er['message']) ?></b><small><?= e($er['page']) ?> · <?= e(sprintf(t('%d time(s)', '%d beses'), (int) $er['count'])) ?> · <?= e(relative_time($er['last_seen'])) ?></small></div></li>
        <?php endforeach; ?>
      </ul>
    <?php endif; ?>
  </div>
  <?php endif; ?>
  <div class="p-card p-card-pad"><p class="p-eyebrow"><?= e(t('How the portal connects', 'Paano kumokonekta ang portal')) ?></p><div id="st-map"></div></div>
  <div class="p-card p-table-card"><div class="p-tscroll"><table class="p-t st-table">
    <thead><tr><th><?= e(t('Service', 'Serbisyo')) ?></th><th><?= e(t('Where it runs', 'Saan tumatakbo')) ?></th><th class="p-right"><?= e(t('Response', 'Tugon')) ?></th><th><?= e(t('Status', 'Katayuan')) ?></th></tr></thead>
    <tbody id="st-rows"></tbody></table></div></div>
  <p class="st-note"><?= e(t('Supabase, Cloudinary and push alerts are checked from the portal\'s server; maps, address lookup, rain data, live updates and the flood map from this browser, so a failure there can also mean this computer\'s internet connection. No keys or passwords are shown.', 'Sinusuri mula sa server ang Supabase, Cloudinary at push alert; mula sa browser na ito ang mapa, address, ulan, live na update at mapa ng baha.')) ?></p>
</section>

<section class="st-pane" data-pane="usage" hidden>
  <p class="st-note"><?= e(t('Which plan each service is on and how close the barangay is to its limits. Amber at 75%, red at 90%.', 'Kung anong plano ang bawat serbisyo at gaano kalapit sa limitasyon. Dilaw sa 75%, pula sa 90%.')) ?></p>
  <div class="st-plans" id="st-plans"><p class="st-note"><?= e(t('Loading…', 'Naglo-load…')) ?></p></div>
</section>

<script>
(function () {
  const PLACES = <?= json_encode(SERVICE_PLACES) ?>;
  const SB_URL = <?= json_encode(supabase_url()) ?>, SB_KEY = <?= json_encode(supabase_key()) ?>;
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $ = id => document.getElementById(id);

  // Each service: what it does for the barangay, and what a failure means.
  const S = [
    { key: 'db',    job: T('Database', 'Database'), prov: 'Supabase', side: 'L',
      down: T('Complaints and accounts can’t be read or saved.', 'Hindi mabasa o maisave ang mga sumbong at account.') },
    { key: 'auth',  job: T('Sign-in', 'Pag-sign in'), prov: 'Supabase Auth', side: 'L',
      down: T('Nobody can sign in to the portal or the app.', 'Walang makapag-sign in sa portal o sa app.') },
    { key: 'live',  job: T('Live updates', 'Live na update'), prov: 'Supabase Realtime', side: 'L',
      down: T('New complaints won’t appear until the page is refreshed.', 'Hindi lalabas ang bagong sumbong hangga’t hindi nire-refresh.') },
    { key: 'media', job: T('Photos and videos', 'Larawan at video'), prov: 'Cloudinary', side: 'L',
      down: T('Residents’ photos and videos won’t upload or show.', 'Hindi maa-upload o makikita ang mga larawan at video.') },
    { key: 'push',  job: T('Push alerts', 'Push alert'), prov: 'Firebase, via send-dispatch-push', side: 'L',
      down: T('Push alerts to tanod phones are not going out. Call or text the tanod on duty.', 'Hindi naipapadala ang push alert sa mga tanod. Tawagan o i-text ang naka-duty.') },
    { key: 'tiles', job: T('Map tiles', 'Mapa'), prov: 'OpenFreeMap', side: 'R',
      down: T('The map shows no streets.', 'Walang kalye sa mapa.') },
    { key: 'geo',   job: T('Address lookup', 'Paghahanap ng address'), prov: 'OpenStreetMap Nominatim', side: 'R',
      down: T('New pins won’t get a street address.', 'Walang address ang bagong pin.') },
    { key: 'rain',  job: T('Rain data', 'Datos ng ulan'), prov: 'Open-Meteo · flood watch', side: 'R',
      down: T('Flood watch shows offline; flood zones stay manual.', 'Offline ang bantay-baha.') },
    { key: 'noah',  job: T('Flood zones', 'Bahaing lugar'), prov: 'Project NOAH map, stored with the portal', side: 'R',
      down: T('The flood zones can’t be drawn on the map.', 'Hindi maiguguhit ang mga bahaing lugar.') },
  ];
  const R = {};   // key -> {state: 'checking'|'ok'|'slow'|'down', ms}
  const SLOW = 1500;

  function timed(p) { const t0 = performance.now(); return p.then(ok => ({ ok, ms: Math.round(performance.now() - t0) }), () => ({ ok: false, ms: null })); }
  function reach(url) { return timed(fetch(url, { cache: 'no-store', mode: 'cors' }).then(r => r.ok)); }
  function realtime() {
    return timed(new Promise((res) => {
      let done = false; const ws = new WebSocket(SB_URL.replace(/^http/, 'ws') + '/realtime/v1/websocket?apikey=' + encodeURIComponent(SB_KEY) + '&vsn=1.0.0');
      const end = ok => { if (done) return; done = true; try { ws.close(); } catch (e) {} res(ok); };
      ws.onopen = () => end(true); ws.onerror = () => end(false); setTimeout(() => end(false), 8000);
    }));
  }
  function set(key, r) { R[key] = { state: !r.ok ? 'down' : (r.ms != null && r.ms > SLOW ? 'slow' : 'ok'), ms: r.ms }; render(); }

  async function check() {
    S.forEach(s => R[s.key] = { state: 'checking' }); render();
    const server = fetch('settings.php?check=server', { cache: 'no-store' }).then(r => r.json()).catch(() => null);
    reach('https://tiles.openfreemap.org/planet').then(r => set('tiles', r));
    reach('https://nominatim.openstreetmap.org/status?format=json').then(r => set('geo', r));
    reach('https://api.open-meteo.com/v1/forecast?latitude=14.5269&longitude=121.0155&current=precipitation').then(r => set('rain', r));
    reach('assets/map/hazards.geojson').then(r => set('noah', r));
    realtime().then(r => set('live', r));
    const sv = await server;
    ['db', 'auth', 'push', 'media'].forEach(k => set(k, sv && sv[k] ? sv[k] : { ok: false, ms: null }));
    $('st-checked').textContent = T('Checked ', 'Sinuri ') + new Date().toLocaleTimeString(window.LANG === 'fil' ? 'fil-PH' : 'en-US', { hour: 'numeric', minute: '2-digit' });
  }

  const BADGE = { ok: ['p-b-done', T('Working', 'Gumagana'), '#22c55e'], slow: ['p-b-pending', T('Slow', 'Mabagal'), '#f59e0b'], down: ['p-b-denied', T('Down', 'Hindi gumagana'), '#ef4444'], checking: ['p-b-grey', T('Checking…', 'Sinusuri…'), '#9AA1AB'] };
  const fmtMs = ms => ms == null ? '—' : ms >= 1000 ? (ms / 1000).toFixed(1) + ' s' : ms + ' ms';

  function render() {
    const st = k => (R[k] || {}).state || 'checking';
    const bad = S.filter(s => st(s.key) === 'down'), slow = S.filter(s => st(s.key) === 'slow'), busy = S.some(s => st(s.key) === 'checking');
    const tone = bad.length ? 'down' : slow.length ? 'slow' : busy ? 'checking' : 'ok';
    const b = $('st-banner'); b.dataset.tone = tone;
    const head = tone === 'checking' ? T('Checking every connection…', 'Sinusuri ang bawat koneksyon…')
      : tone === 'ok' ? T('Everything is working', 'Gumagana ang lahat')
      : [bad.length ? bad.length + T(bad.length === 1 ? ' service down' : ' services down', ' hindi gumagana') : '', slow.length ? slow.length + T(' slow', ' mabagal') : ''].filter(Boolean).join(', ');
    const why = tone === 'ok' ? T('Complaints, sign-in, photos, push alerts, maps and flood data are all reachable.', 'Naaabot ang lahat ng serbisyo.')
      : tone === 'checking' ? '' : [...bad.map(s => s.down), ...slow.map(s => s.job + T(' is answering slowly.', ' ay mabagal.'))].join(' ') + (S.length - bad.length - slow.length > 0 ? ' ' + T('Everything else is working.', 'Gumagana ang iba.') : '');
    b.innerHTML = '<span class="st-big"></span><span><b>' + esc(head) + '</b><small>' + esc(why) + '</small></span>';

    $('st-rows').innerHTML = S.map(s => { const r = R[s.key] || {}, B = BADGE[r.state || 'checking'], pl = PLACES[s.key];
      return '<tr><td><b>' + esc(s.job) + '</b><small>' + esc(s.prov) + '</small></td><td><span class="st-where"><span class="st-cc">' + esc(pl[0]) + '</span>' + esc(pl[1]) + '</span></td>' +
        '<td class="st-ms">' + (r.state === 'checking' ? '…' : s.key === 'noah' && r.state === 'ok' ? 'local' : fmtMs(r.ms)) + '</td><td><span class="p-badge ' + B[0] + '">' + esc(B[1]) + '</span></td></tr>'; }).join('');

    // The system map: the portal in the middle, a line to each service in its state's colour.
    const W = 640, H = 310, cx = 320, cy = 155, L = S.filter(s => s.side === 'L'), Rt = S.filter(s => s.side === 'R');
    const ys = (arr, i) => 20 + i * ((H - 70) / Math.max(1, arr.length - 1));
    let svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="' + esc(T('Diagram of the portal and the services it connects to', 'Diagram ng portal at mga serbisyo')) + '">';
    const nodes = [];
    L.forEach((s, i) => nodes.push([s, 10, ys(L, i)])); Rt.forEach((s, i) => nodes.push([s, 470, ys(Rt, i)]));
    nodes.forEach(([s, x, y]) => { const r = R[s.key] || {}, c = BADGE[r.state || 'checking'][2], tx = s.side === 'L' ? x + 160 : x;
      svg += '<path class="st-flow' + (r.state === 'down' ? ' st-bad' : '') + '" stroke="' + c + '" d="M' + cx + ' ' + cy + ' C ' + (s.side === 'L' ? cx - 90 : cx + 90) + ' ' + cy + ' ' + (s.side === 'L' ? tx + 50 : tx - 50) + ' ' + (y + 15) + ' ' + tx + ' ' + (y + 15) + '"/>'; });
    svg += '<rect x="' + (cx - 75) + '" y="' + (cy - 30) + '" width="150" height="60" rx="14" fill="#00308F"/><text x="' + cx + '" y="' + (cy - 4) + '" text-anchor="middle" class="st-hub">SmartSumbong</text><text x="' + cx + '" y="' + (cy + 14) + '" text-anchor="middle" class="st-hub2">portal · Render</text>';
    const short = { db: 'Supabase', auth: 'Supabase', live: 'Supabase', media: 'Cloudinary', push: 'Firebase', tiles: 'OpenFreeMap', geo: 'Nominatim', rain: 'Open-Meteo', noah: 'Project NOAH' };
    nodes.forEach(([s, x, y]) => { const r = R[s.key] || {}, c = BADGE[r.state || 'checking'][2];
      svg += '<g class="st-node"><rect x="' + x + '" y="' + y + '" width="160" height="30" rx="8"/><circle cx="' + (x + 14) + '" cy="' + (y + 15) + '" r="4.5" fill="' + c + '"/>' +
        '<text x="' + (x + 26) + '" y="' + (y + 13) + '" class="st-t">' + esc(s.job.length > 22 ? s.job.slice(0, 21) + '…' : s.job) + '</text>' +
        '<text x="' + (x + 26) + '" y="' + (y + 25) + '" class="st-s">' + esc(short[s.key]) + ' · ' + (r.state === 'checking' ? '…' : s.key === 'noah' && r.state === 'ok' ? 'local' : fmtMs(r.ms)) + '</text></g>'; });
    $('st-map').innerHTML = svg + '</svg>';
  }

  // Plan and usage.
  const mb = b => b == null ? '—' : b >= 1073741824 ? (b / 1073741824).toFixed(2) + ' GB' : (b / 1048576).toFixed(1) + ' MB';
  function meter(label, val, pct) {
    const cls = pct == null ? '' : pct >= 90 ? 'b' : pct >= 75 ? 'w' : '';
    return '<div class="st-meter"><div class="st-lbl"><span>' + esc(label) + '</span><span>' + esc(val) + '</span></div>' +
      (pct == null ? '' : '<div class="st-bar"><i class="' + cls + '" style="width:' + Math.max(1.5, Math.min(100, pct)) + '%"></i></div>') + '</div>';
  }
  function card(name, tier, body, catchTxt, foot) {
    return '<div class="p-card p-card-pad st-plan"><header><b>' + esc(name) + '</b>' + (tier ? '<span class="st-tier">' + esc(tier) + '</span>' : '') + '</header>' + body +
      (catchTxt ? '<div class="st-catch">' + catchTxt + '</div>' : '') + (foot ? '<span class="st-foot">' + foot + '</span>' : '') + '</div>';
  }
  async function usage() {
    let u = null; try { u = await fetch('settings.php?usage=1', { cache: 'no-store' }).then(r => r.json()); } catch (e) {}
    if (!u) { $('st-plans').innerHTML = '<p class="st-note">' + esc(T('Usage could not be loaded. Try again.', 'Hindi ma-load. Subukan muli.')) + '</p>'; return; }
    const sb = u.supabase, P = u.plans || {}, next = new Date(); next.setMonth(next.getMonth() + 1, 1);
    const resets = T('Resets ', 'Magre-reset sa ') + next.toLocaleDateString(window.LANG === 'fil' ? 'fil-PH' : 'en-US', { month: 'short', day: 'numeric' });
    const cards = [];
    cards.push(card('Supabase', P.supabase,
      sb ? meter(T('Database', 'Database'), mb(sb.db_bytes) + ' ' + T('of', 'sa') + ' 500 MB', sb.db_bytes / 524288000 * 100)
         + meter(T('File storage', 'Imbakan'), mb(sb.storage_bytes) + ' ' + T('of', 'sa') + ' 1 GB', sb.storage_bytes / 1073741824 * 100)
         + meter(T('Active users this month', 'Aktibong user ngayong buwan'), Number(sb.active_users).toLocaleString() + ' ' + T('of', 'sa') + ' 50,000', sb.active_users / 50000 * 100)
         : '<p class="st-note">' + esc(T('Database size and active users need the system_usage function (migration 0078).', 'Kailangan ang migration 0078.')) + '</p>',
      esc(T('Free projects pause after a week with no activity. Data sent out is shown only in Supabase’s dashboard.', 'Humihinto ang libreng proyekto pagkalipas ng isang linggong walang aktibidad.')),
      esc(resets) + ' · ' + esc(T('limits shown are the Free plan’s', 'limitasyon ng Free plan'))));
    const cl = u.cloudinary, ph = u.photos;
    cards.push(card('Cloudinary', cl && cl.plan ? cl.plan : P.cloudinary,
      (cl && cl.credits_limit ? meter(T('Monthly credits', 'Buwanang credit'), (+cl.credits_used).toFixed(1) + ' ' + T('of', 'sa') + ' ' + cl.credits_limit, cl.credits_used / cl.credits_limit * 100) : '')
      + (ph ? meter(T('Complaint photos on record', 'Mga larawan sa talaan'), ph.files.toLocaleString() + ' · ' + mb(ph.bytes), null) : ''),
      cl ? esc(T('1 credit = 1 GB stored, 1 GB served or 1,000 resizes.', '1 credit = 1 GB imbak, 1 GB ipinadala o 1,000 resize.'))
         : esc(T('Credits aren’t connected yet: add CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET to the server’s environment in Render to see them here.', 'Idagdag ang CLOUDINARY_API_KEY at CLOUDINARY_API_SECRET sa server.')),
      esc(T('Photos on record are counted from the database', 'Binilang mula sa database'))));
    cards.push(card('Render', P.render, '',
      esc(T('On the Free plan the portal sleeps after 15 minutes with no visitors; the next visit takes about a minute to wake it. Open it a minute before presenting.', 'Natutulog ang portal pagkalipas ng 15 minutong walang bisita.')),
      esc(T('750 instance hours a month on the Free plan', '750 oras bawat buwan sa Free plan'))));
    cards.push(card(T('Firebase push', 'Firebase push'), T('No cost', 'Walang bayad'),
      u.alerts != null ? meter(T('Dispatch alerts this month', 'Dispatch alert ngayong buwan'), Number(u.alerts).toLocaleString(), null) : '', '',
      esc(T('Cloud Messaging has no usage charge', 'Walang singil ang Cloud Messaging'))));
    cards.push(card('Open-Meteo', 'Free', meter(T('Rain checks allowed', 'Pinapayagang pagsuri'), T('10,000 a day', '10,000 bawat araw'), null), '',
      esc(T('Free for non-commercial use · each open map checks every 10 minutes', 'Libre para sa hindi pangkomersyo · bawat 10 minuto'))));
    cards.push(card('Nominatim · OpenFreeMap', 'Free', meter(T('Address lookups', 'Paghahanap ng address'), T('at most 1 per second', 'hanggang 1 bawat segundo'), null), '',
      esc(T('OpenFreeMap tiles have no limit', 'Walang limitasyon ang OpenFreeMap'))));
    $('st-plans').innerHTML = cards.join('');
  }

  document.querySelectorAll('.st-tabs [data-st]').forEach(b => b.addEventListener('click', () => {
    document.querySelectorAll('.st-tabs [data-st]').forEach(x => x.classList.toggle('p-on', x === b));
    document.querySelectorAll('.st-pane').forEach(p => p.hidden = p.dataset.pane !== b.dataset.st);
  }));
  $('st-check').addEventListener('click', () => { check(); usage(); });
  check(); usage();
})();
</script>
<script>
// Back on the Administrators tab after adding or resetting.
if (location.hash === '#admins') { var b = document.querySelector('.st-tabs [data-st="admins"]'); if (b) b.click(); }
</script>
<?php layout_foot(); ?>
