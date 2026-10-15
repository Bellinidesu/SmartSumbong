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
// 0130 (defense, 7 Sep): the barangay's positions. Which Kagawad chairs which committee, who is the Chairman, which tanods are the
// designated women responders, and which committee usually takes which kind of complaint. Each is one action here.
const CATEGORY_POINT_LABELS = [
    'public_safety_infrastructure' => ['Public safety', 'Kaligtasan ng publiko'],
    'peace_order_nuisance'         => ['Peace and order', 'Kapayapaan at kaayusan'],
    'environmental_waste_hazard'   => ['Environment and waste', 'Kapaligiran at basura'],
    'traffic_violation'            => ['Traffic', 'Trapiko'],
    'street_obstruction'           => ['Street obstruction', 'Sagabal sa kalsada'],
    'animal_welfare'               => ['Animal welfare', 'Kapakanan ng hayop'],
    'barangay_service'             => ['Barangay service', 'Serbisyo ng barangay'],
    'other'                        => ['Other', 'Iba pa'],
];
const COMMITTEES = [
    'peace_order'       => ['Peace and Order', 'Kapayapaan at Kaayusan'],
    'health_sanitation' => ['Health and Sanitation', 'Kalusugan at Kalinisan'],
    'education'         => ['Education', 'Edukasyon'],
    'infrastructure'    => ['Infrastructure', 'Imprastraktura'],
    'environment'       => ['Environment', 'Kapaligiran'],
    'women_family'      => ['Women and Family', 'Kababaihan at Pamilya'],
    'youth_sports'      => ['Youth and Sports', 'Kabataan at Palakasan'],
    'agriculture'       => ['Agriculture', 'Agrikultura'],
    'appropriations'    => ['Appropriations', 'Pondo'],
];
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['set_role', 'set_responder', 'set_committee_map'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $uid = (string) ($_POST['user'] ?? '');
            if ($_POST['action'] === 'set_role') {
                $role = (string) ($_POST['official_role'] ?? '');
                $comm = (string) ($_POST['committee'] ?? '');
                $db->rpc('set_official_role', ['p_user' => $uid, 'p_role' => $role === '' ? null : $role,
                                              'p_committee' => $role === 'kagawad' && isset(COMMITTEES[$comm]) ? $comm : null, 'p_women' => null]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Position saved.', 'Nai-save ang posisyon.')];
            } elseif ($_POST['action'] === 'set_responder') {
                $db->rpc('set_official_role', ['p_user' => $uid, 'p_role' => null, 'p_committee' => null, 'p_women' => !empty($_POST['on'])]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Responder designation saved.', 'Nai-save ang pagtatalaga ng responder.')];
            } else {
                $cat = (string) ($_POST['category'] ?? ''); $comm = (string) ($_POST['committee'] ?? '');
                if (isset(COMMITTEES[$comm]) && preg_match('/^[a-z_]+$/', $cat)) {
                    $db->update('committee_for_category', ['category' => 'eq.' . $cat], ['committee' => $comm]);
                    $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Committee saved.', 'Nai-save ang komite.')];
                }
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: settings.php#admins');
    exit;
}

// Settings -> SMART (docs/SMART_SCREENS.md, 6 and 6b): the rules, storm mode, the digest, trying a rule, re-scoring.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && in_array($_POST['action'] ?? '', ['smart_rules', 'smart_storm', 'smart_digest', 'smart_try', 'smart_rescore'], true)) {
    session_start_once();
    if (!csrf_check($_POST['csrf'] ?? null)) {
        $_SESSION['st_flash'] = ['level' => 'error', 'text' => t('That form expired. Please try again.', 'Nag-expire ang form. Subukan muli.')];
    } else {
        try {
            $act = (string) $_POST['action'];
            if ($act === 'smart_rules') {
                $pts = [];
                foreach (array_keys(CATEGORY_POINT_LABELS) as $ck) { $pts[$ck] = max(0, min(60, (int) ($_POST['pts'][$ck] ?? 0))); }
                $db->update('smart_rules', ['id' => 'eq.1'], [
                    'category_points' => $pts,
                    'urgent_from'     => max(1, min(100, (int) ($_POST['urgent_from'] ?? 70))),
                    'high_from'       => max(1, min(100, (int) ($_POST['high_from'] ?? 45))),
                    'normal_from'     => max(1, min(100, (int) ($_POST['normal_from'] ?? 25))),
                    'updated_at'      => gmdate('c'),
                    'updated_by'      => $admin['id'],
                ]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('The rules were saved. Press "Re-score open reports" to apply them to cases already open.', 'Nai-save ang mga patakaran. Pindutin ang "Muling markahan ang mga bukas na ulat" para ilapat sa mga kasong bukas na.')];
            } elseif ($act === 'smart_storm') {
                $on = ($_POST['on'] ?? '') === '1';
                $db->rpc('smart_storm_mode', ['p_on' => $on, 'p_reason' => trim((string) ($_POST['reason'] ?? '')) ?: null, 'p_hours' => max(1, min(168, (int) ($_POST['hours'] ?? 24)))]);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => $on ? t('Storm mode is on.', 'Naka-on ang storm mode.') : t('Storm mode is off.', 'Naka-off ang storm mode.')];
            } elseif ($act === 'smart_digest') {
                $db->update('smart_rules', ['id' => 'eq.1'], ['digest_enabled' => ($_POST['on'] ?? '') === '1']);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => t('Saved.', 'Nai-save.')];
            } elseif ($act === 'smart_rescore') {
                $n = $db->rpc('smart_retriage', []);
                $_SESSION['st_flash'] = ['level' => 'info', 'text' => sprintf(t('%d open reports were re-scored.', '%d na bukas na ulat ang muling minarkahan.'), (int) $n)];
            } else {
                $cat = (string) ($_POST['category'] ?? '');
                $lat = trim((string) ($_POST['lat'] ?? '')); $lng = trim((string) ($_POST['lng'] ?? ''));
                $_SESSION['smart_try'] = $db->rpc('smart_preview', [
                    'p_category' => $cat, 'p_subject' => trim((string) ($_POST['subject'] ?? '')), 'p_description' => trim((string) ($_POST['description'] ?? '')),
                    'p_lat' => is_numeric($lat) ? (float) $lat : null, 'p_lng' => is_numeric($lng) ? (float) $lng : null]);
            }
        } catch (SupabaseError $ex) {
            $_SESSION['st_flash'] = ['level' => 'error', 'text' => safe_error($ex)];
        }
    }
    header('Location: settings.php#smart');
    exit;
}

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
  <button type="button" role="tab" data-st="smart">SMART</button>
  <button type="button" role="tab" data-st="look"><?= e(t('Appearance', 'Itsura')) ?></button>
</div>

<?php
// Rose (5 Oct 2026): every administrator, and whether they still hold a
// temporary password. Adding one from here comes with the account service.
$stFlash = $_SESSION['st_flash'] ?? null;
unset($_SESSION['st_flash']);
$admins = [];
try {
    $admins = $db->select('users', [
        'select' => 'id,full_name,email,must_change_password,is_suspended,created_at,official_role,committee',
        'role'   => 'eq.admin',
        'order'  => 'created_at.asc',
    ]);
    $tanods  = $db->select('users', ['select' => 'id,full_name,women_responder', 'role' => 'eq.tanod', 'is_suspended' => 'is.false', 'order' => 'full_name.asc']);
    $cmap    = $db->select('committee_for_category', ['select' => 'category,committee', 'order' => 'category.asc']);
} catch (SupabaseError $e) { $admins = []; $tanods = []; $cmap = []; }
?>
<section class="st-pane" data-pane="admins" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'ok'): ?>
    <div class="p-flash p-flash--ok" role="status">
      <?= e(!empty($stFlash['new']) ? t('Account created. A link to set a password was emailed to', 'Nagawa ang account. Naipadala ang link para magtakda ng password sa') : t('A link to set a new password was emailed to', 'Naipadala ang link para magtakda ng bagong password sa')) ?>
      <b><?= e($stFlash['who']) ?></b>. <?= e(t('Only they can see it.', 'Sila lang ang makakakita nito.')) ?>
    </div>
  <?php elseif ($stFlash && $stFlash['level'] === 'info'): ?>
    <div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash): ?>
    <div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div>
  <?php endif; ?>
  <?php $roleOpts = ['' => t('Staff', 'Kawani'), 'secretary' => t('Secretary', 'Kalihim'), 'kagawad' => t('Councilor (Kagawad)', 'Kagawad'), 'chairman' => t('Chairman', 'Punong Barangay')]; ?>
  <div class="p-band ss-pband">
    <h2><?= e(t('Administrators', 'Mga Administrator')) ?><span class="p-badge-n p-badge-n--quiet" id="jp-count"><?= count($admins) ?></span></h2>
    <form class="p-search" role="search" onsubmit="return false">
      <?= p_icon('i-search', 16) ?><label class="p-sr" for="jp-q"><?= e(t('Search for names', 'Hanapin ang pangalan')) ?></label>
      <input type="search" id="jp-q" placeholder="<?= e(t('Search for names', 'Hanapin ang pangalan')) ?>" autocomplete="off">
    </form>
    <span class="p-spacer"></span>
    <label class="p-pill-select"><span class="p-lbl"><?= e(t('Position', 'Posisyon')) ?></span>
      <select id="jp-role" aria-label="<?= e(t('Position', 'Posisyon')) ?>"><option value=""><?= e(t('All', 'Lahat')) ?></option>
        <?php foreach ($roleOpts as $rv => $rl): ?><option value="<?= $rv === '' ? 'staff' : e($rv) ?>"><?= e($rl) ?></option><?php endforeach; ?>
      </select></label>
    <button type="button" class="jp-add" id="jp-add" aria-controls="jp-addcard" aria-expanded="false"><?= e(t('Add administrator', 'Magdagdag ng administrator')) ?></button>
  </div>
  <div class="p-card p-table-card jp-card ss-adm"><div class="p-tscroll"><table class="p-t jp-t ss-ohead">
    <thead><tr>
      <th scope="col"><?= e(t('Name', 'Pangalan')) ?></th>
      <th scope="col"><?= e(t('Position', 'Posisyon')) ?></th>
      <th scope="col"><?= e(t('Committee', 'Komite')) ?></th>
      <th scope="col"><?= e(t('Status', 'Katayuan')) ?></th>
      <th scope="col"><?= e(t('Online now', 'Online ngayon')) ?></th>
      <th scope="col" class="p-right"><span class="p-sr"><?= e(t('Actions', 'Mga aksyon')) ?></span></th>
    </tr></thead>
    <tbody id="jp-rows">
    <?php foreach ($admins as $a): $fid = 'role-' . $a['id']; $isK = ($a['official_role'] ?? '') === 'kagawad'; ?>
      <tr data-name="<?= e(strtolower(($a['full_name'] ?? '') . ' ' . ($a['email'] ?? ''))) ?>" data-role="<?= e(($a['official_role'] ?? '') === '' ? 'staff' : (string) $a['official_role']) ?>">
        <td>
          <div class="jp-who"><?= admin_chip($a['id'], (string) $a['full_name'], 32) ?>
            <span><b><?= e(formal_name($a['full_name'])) ?><?= $a['id'] === $admin['id'] ? ' <small>(' . e(t('you', 'ikaw')) . ')</small>' : '' ?></b>
              <small><?= e((string) ($a['email'] ?? '')) ?></small></span></div>
          <form method="post" id="<?= e($fid) ?>" class="ss-jrole">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="set_role">
            <input type="hidden" name="user" value="<?= e($a['id']) ?>">
          </form>
        </td>
        <td>
          <label class="p-sr" for="pos-<?= e($a['id']) ?>"><?= e(t('Position', 'Posisyon')) ?></label>
          <select class="jp-sel" form="<?= e($fid) ?>" id="pos-<?= e($a['id']) ?>" name="official_role" data-role-sel>
            <?php foreach ($roleOpts as $rv => $rl): ?><option value="<?= e($rv) ?>" <?= ($a['official_role'] ?? '') === $rv ? 'selected' : '' ?>><?= e($rl) ?></option><?php endforeach; ?>
          </select>
        </td>
        <td>
          <label class="p-sr" for="cm-<?= e($a['id']) ?>"><?= e(t('Committee', 'Komite')) ?></label>
          <select class="jp-sel" form="<?= e($fid) ?>" id="cm-<?= e($a['id']) ?>" name="committee" data-comm-sel <?= $isK ? '' : 'disabled' ?>
                  title="<?= e(t('Pick a committee for a Kagawad', 'Pumili ng komite para sa Kagawad')) ?>">
            <option value=""><?= e(t('No committee', 'Walang komite')) ?></option>
            <?php foreach (COMMITTEES as $cv => $cl): ?><option value="<?= e($cv) ?>" <?= ($a['committee'] ?? '') === $cv ? 'selected' : '' ?>><?= e(t($cl[0], $cl[1])) ?></option><?php endforeach; ?>
          </select>
        </td>
        <td><?php if (!empty($a['is_suspended'])): ?><span class="jp-lz jp-lz--bad"><?= e(t('Suspended', 'Suspendido')) ?></span><?php elseif (!empty($a['must_change_password'])): ?><span class="jp-lz jp-lz--warn"><?= e(t('Must change password', 'Kailangang palitan ang password')) ?></span><?php else: ?><span class="jp-lz jp-lz--ok"><?= e(t('Active', 'Aktibo')) ?></span><?php endif; ?></td>
        <td class="ss-online" data-admin="<?= e($a['id']) ?>"><span class="ss-dot"></span><?= e(t('Offline', 'Offline')) ?></td>
        <td class="p-right"><?php if ($a['id'] !== $admin['id']): ?>
          <details class="jp-more"><summary aria-label="<?= e(t('More actions', 'Iba pang aksyon')) ?>">&#8943;</summary>
            <div class="jp-menu">
              <form method="post" data-captcha data-native-confirm="<?= e(t('Email this administrator a link to set a new password?', 'I-email sa administrator na ito ang link para magtakda ng bagong password?')) ?>">
                <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
                <input type="hidden" name="action" value="reset_admin">
                <input type="hidden" name="user" value="<?= e($a['id']) ?>">
                <input type="hidden" name="email" value="<?= e((string) ($a['email'] ?? '')) ?>">
                <button type="submit"><?= e(t('Email a password link', 'I-email ang link ng password')) ?></button>
              </form>
            </div>
          </details>
        <?php endif; ?></td>
      </tr>
    <?php endforeach; ?>
    <tr id="jp-none" hidden><td colspan="6" class="p-empty"><?= e(t('No administrator matches that.', 'Walang administrator na tugma.')) ?></td></tr>
    </tbody>
  </table></div></div>
  <div class="p-card p-card-pad ss-posinfo">
    <p class="p-eyebrow"><?= e(t('Layered escalation', 'Patong-patong na eskalasyon')) ?></p>
    <p class="p-hint"><?= e(t('A case goes up one step at a time: the Tanod, then the Kagawad of the committee that usually takes that kind of complaint, then the Chairman. A Kagawad needs a committee; there is one Chairman. Nothing moves by itself.', 'Isang hakbang bawat akyat ng kaso: ang Tanod, saka ang Kagawad ng komiteng karaniwang may hawak ng ganoong reklamo, saka ang Punong Barangay. Kailangan ng komite ang Kagawad; iisa ang Punong Barangay. Walang kusang gumagalaw.')) ?></p>
    <p class="p-label"><?= e(t('Which committee takes which complaint', 'Aling komite ang may hawak ng aling reklamo')) ?></p>
    <div class="ss-cmap">
      <?php foreach ($cmap as $m): ?>
        <form method="post" class="ss-cmap-row">
          <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
          <input type="hidden" name="action" value="set_committee_map">
          <input type="hidden" name="category" value="<?= e($m['category']) ?>">
          <span><?= e(category_label((string) $m['category'])) ?></span>
          <select class="p-input-plain" name="committee" data-autosubmit aria-label="<?= e(category_label((string) $m['category'])) ?>">
            <?php foreach (COMMITTEES as $cv => $cl): ?><option value="<?= e($cv) ?>" <?= $m['committee'] === $cv ? 'selected' : '' ?>><?= e(t($cl[0], $cl[1])) ?></option><?php endforeach; ?>
          </select>
        </form>
      <?php endforeach; ?>
    </div>
  </div>
  <div class="p-card p-card-pad ss-posinfo">
    <p class="p-eyebrow"><?= e(t('Women responders', 'Mga responder para sa kababaihan')) ?></p>
    <p class="p-hint"><?= e(t('Tanods designated for women and children cases (the VAWC desk). Sensitive cases show them first when a tanod is chosen.', 'Mga tanod na itinalaga sa mga kaso ng kababaihan at bata (VAWC desk). Una silang ipinapakita sa mga sensitibong kaso kapag pipili ng tanod.')) ?></p>
    <?php if (!$tanods): ?><p class="p-none-line"><?= e(t('No tanod accounts yet.', 'Wala pang account ng tanod.')) ?></p><?php endif; ?>
    <?php foreach ($tanods as $tn): ?>
      <form method="post" class="ss-resp-row">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <input type="hidden" name="action" value="set_responder">
        <input type="hidden" name="user" value="<?= e($tn['id']) ?>">
        <label class="sd-c"><input type="checkbox" name="on" value="1" data-autosubmit <?= !empty($tn['women_responder']) ? 'checked' : '' ?>> <?= e(formal_name($tn['full_name'])) ?></label>
      </form>
    <?php endforeach; ?>
  </div>
  <div class="p-card p-card-pad ss-addadmin" id="jp-addcard" hidden>
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
  <div class="p-card p-card-pad st-credits"><p class="p-eyebrow"><?= e(t('Map credits', 'Mga kredito ng mapa')) ?></p>
    <p class="st-credit-line"><?= e(t('Map data © OpenStreetMap contributors (ODbL) · tiles by OpenFreeMap and OpenMapTiles · building footprints also from Overture Maps (Google Open Buildings, Microsoft ML Buildings) · tree heights from the Meta and World Resources Institute canopy height map (CC BY 4.0) · floor counts from Overture Maps and OpenStreetMap · flood hazard maps © UP NOAH Center (Project NOAH) · air quality and rain by Open-Meteo · street imagery © Mapillary contributors (CC BY-SA) · photos from Wikimedia Commons, credited where shown · icons from Lucide (ISC) and Tabler Icons (MIT).', 'Datos ng mapa © OpenStreetMap contributors (ODbL) · tiles mula sa OpenFreeMap at OpenMapTiles · mga hugis ng gusali mula rin sa Overture Maps (Google Open Buildings, Microsoft ML Buildings) · taas ng puno mula sa canopy height map ng Meta at World Resources Institute (CC BY 4.0) · mapa ng baha © UP NOAH Center (Project NOAH) · kalidad ng hangin at ulan mula sa Open-Meteo · street imagery © Mapillary contributors (CC BY-SA) · mga larawan mula sa Wikimedia Commons, may kredito kung saan ipinapakita · mga icon mula sa Lucide (ISC) at Tabler Icons (MIT).')) ?></p></div>
</section>

<?php
// ---------- SMART ----------
$sr = null; $cal = []; $fac = []; $digest = '';
$try = $_SESSION['smart_try'] ?? null; unset($_SESSION['smart_try']);
try {
    $got = $db->selectMany([
        'rules'  => ['smart_rules', ['select' => '*', 'id' => 'eq.1', 'limit' => '1'], true],
        'cal'    => ['rpc/smart_calibration', ['p_days' => 90], true],
        'fac'    => ['rpc/smart_factor_stats', ['p_days' => 90], true],
        'digest' => ['rpc/smart_digest_preview', [], true],
    ]);
    $sr     = !($got['rules'] instanceof SupabaseError) ? ($got['rules'][0] ?? null) : null;
    $cal    = !($got['cal'] instanceof SupabaseError) ? (array) $got['cal'] : [];
    $fac    = !($got['fac'] instanceof SupabaseError) ? array_slice((array) $got['fac'], 0, 12) : [];
    $digest = !($got['digest'] instanceof SupabaseError) && is_string($got['digest']) ? $got['digest'] : '';
} catch (SupabaseError) { /* the tab says so below */ }
$lvl = ['low' => t('Low', 'Mababa'), 'normal' => t('Normal', 'Katamtaman'), 'high' => t('High', 'Mataas'), 'urgent' => t('Urgent', 'Madalian')];
?>
<section class="st-pane" data-pane="smart" hidden>
  <?php if ($stFlash && $stFlash['level'] === 'info'): ?><div class="p-flash p-flash--ok" role="status"><?= e($stFlash['text']) ?></div>
  <?php elseif ($stFlash && $stFlash['level'] === 'error'): ?><div class="p-flash p-flash--error" role="alert"><?= e($stFlash['text']) ?></div><?php endif; ?>
  <div class="ss-head"><?= smart_logo(44) ?><p><?= e(t('How the engine scores and sorts complaints. Change a rule, try it, then re-score.', 'Paano minamarkahan at inaayos ng engine ang mga sumbong. Baguhin ang patakaran, subukan, saka muling markahan.')) ?></p></div>
  <?php if (!$sr): ?>
    <p class="p-none-line"><?= e(t('SMART could not be read. Try again in a moment.', 'Hindi mabasa ang SMART. Subukan muli mamaya.')) ?></p>
  <?php else: ?>
  <div class="ss-two">
    <div class="p-card p-card-pad">
      <p class="p-eyebrow"><?= e(t('Storm mode', 'Panahon ng bagyo')) ?></p>
      <p class="p-hint"><?= e(t('While it is on, flood zones and flood, live-wire and collapse reports count double, and the case list says so.', 'Habang naka-on, doble ang bilang ng mga lugar na binabaha at ng mga ulat ng baha, nakakuryente at pagguho.')) ?></p>
      <?php if (!empty($sr['storm_mode'])): ?>
        <p><b><?= e(t('On until', 'Naka-on hanggang')) ?> <?= e((new DateTimeImmutable((string) $sr['storm_until']))->setTimezone(new DateTimeZone('Asia/Manila'))->format('M j, g:i A')) ?></b><?= !empty($sr['storm_reason']) ? ' · ' . e((string) $sr['storm_reason']) : '' ?></p>
        <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_storm"><input type="hidden" name="on" value="0">
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('End storm mode', 'Tapusin ang storm mode')) ?></button></form>
      <?php else: ?>
        <form method="post" class="p-ctl-stack"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_storm"><input type="hidden" name="on" value="1">
          <div class="p-cfield"><label class="p-flabel" for="sm-why"><?= e(t('Why (for example, the PAGASA warning)', 'Bakit (halimbawa, babala ng PAGASA)')) ?></label><input class="p-input-plain" id="sm-why" name="reason" required minlength="3" maxlength="200"></div>
          <div class="p-cfield"><label class="p-flabel" for="sm-h"><?= e(t('Hours', 'Oras')) ?></label><input class="p-input-plain" id="sm-h" type="number" name="hours" min="1" max="168" value="24"></div>
          <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Turn on', 'I-on')) ?></button></form>
      <?php endif; ?>
    </div>
    <div class="p-card p-card-pad">
      <p class="p-eyebrow"><?= e(t('Morning digest', 'Buod sa umaga')) ?></p>
      <p class="p-hint"><?= e(t('A short note each morning to the administrators: what is urgent, what may miss its deadline, what keeps coming back.', 'Maikling paalala tuwing umaga sa mga administrator: ano ang madalian, ano ang maaaring lumampas sa oras, ano ang paulit-ulit.')) ?></p>
      <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_digest">
        <label class="sd-c"><input type="checkbox" name="on" value="1" data-autosubmit <?= !empty($sr['digest_enabled']) ? 'checked' : '' ?>> <?= e(t('Send it', 'Ipadala')) ?></label></form>
      <?php if ($digest !== ''): ?><p class="ss-digest"><?= nl2br(e($digest)) ?></p><?php endif; ?>
    </div>
  </div>

  <form method="post" class="p-card p-card-pad">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_rules">
    <p class="p-eyebrow"><?= e(t('Points for each kind of complaint', 'Puntos sa bawat uri ng sumbong')) ?></p>
    <p class="p-hint"><?= e(t('A report starts with these points; words, hazard zones, neighbours reporting the same thing and the hour add to them. The total decides the level.', 'Nagsisimula ang ulat sa mga puntos na ito; dinadagdagan ito ng mga salita, lugar na may panganib, kapitbahay na nag-ulat ng pareho at oras. Ang kabuuan ang magpapasya ng antas.')) ?></p>
    <div class="ss-cmap">
      <?php foreach (CATEGORY_POINT_LABELS as $ck => $cl): ?>
        <div class="ss-cmap-row"><label for="pt-<?= e($ck) ?>"><?= e(t($cl[0], $cl[1])) ?></label>
          <input class="p-input-plain" id="pt-<?= e($ck) ?>" type="number" name="pts[<?= e($ck) ?>]" min="0" max="60" value="<?= (int) ($sr['category_points'][$ck] ?? 0) ?>"></div>
      <?php endforeach; ?>
    </div>
    <p class="p-eyebrow" style="margin-top:14px"><?= e(t('Where the levels start (out of 100)', 'Kung saan nagsisimula ang mga antas (sa 100)')) ?></p>
    <div class="ss-cmap ss-cmap--3">
      <?php foreach (['urgent_from' => t('Urgent from', 'Madalian mula'), 'high_from' => t('High from', 'Mataas mula'), 'normal_from' => t('Normal from', 'Katamtaman mula')] as $fk => $fl): ?>
        <div class="ss-cmap-row"><label for="lv-<?= e($fk) ?>"><?= e($fl) ?></label><input class="p-input-plain" id="lv-<?= e($fk) ?>" type="number" name="<?= e($fk) ?>" min="1" max="100" value="<?= (int) $sr[$fk] ?>"></div>
      <?php endforeach; ?>
    </div>
    <p class="p-hint"><?= e(t('Urgent must be higher than High, and High higher than Normal.', 'Dapat mas mataas ang Madalian kaysa Mataas, at ang Mataas kaysa Katamtaman.')) ?></p>
    <div class="ss-posform"><button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Save rules', 'I-save ang mga patakaran')) ?></button></div>
  </form>
  <form method="post" class="ss-posform"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_rescore">
    <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Re-score open reports', 'Muling markahan ang mga bukas na ulat')) ?></button>
    <span class="p-hint"><?= e(t('Applies the rules above to every case that is still open. Levels an administrator set by hand stay.', 'Ilalapat ang mga patakaran sa lahat ng kasong bukas pa. Mananatili ang antas na itinakda ng administrator.')) ?></span></form>

  <form method="post" class="p-card p-card-pad">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="smart_try">
    <p class="p-eyebrow"><?= e(t('Try it', 'Subukan')) ?></p>
    <p class="p-hint"><?= e(t('Type a complaint and see what level SMART would give it, and why. Nothing is saved.', 'Mag-type ng sumbong at tingnan ang antas na ibibigay ng SMART, at kung bakit. Walang mase-save.')) ?></p>
    <div class="p-ctl-stack">
      <div class="p-cfield"><label class="p-flabel" for="tr-cat"><?= e(t('Kind of complaint', 'Uri ng sumbong')) ?></label>
        <select class="p-input-plain" id="tr-cat" name="category"><?php foreach (CATEGORY_POINT_LABELS as $ck => $cl): ?><option value="<?= e($ck) ?>"><?= e(t($cl[0], $cl[1])) ?></option><?php endforeach; ?></select></div>
      <div class="p-cfield"><label class="p-flabel" for="tr-sub"><?= e(t('Subject', 'Paksa')) ?></label><input class="p-input-plain" id="tr-sub" name="subject" required maxlength="120"></div>
      <div class="p-cfield"><label class="p-flabel" for="tr-desc"><?= e(t('What happened', 'Ano ang nangyari')) ?></label><textarea class="p-note" id="tr-desc" name="description" rows="2" maxlength="600"></textarea></div>
      <div class="p-cfield"><label class="p-flabel" for="tr-lat"><?= e(t('Latitude and longitude (optional)', 'Latitude at longitude (opsyonal)')) ?></label>
        <div class="ss-posform"><input class="p-input-plain" id="tr-lat" name="lat" inputmode="decimal" placeholder="14.5"><input class="p-input-plain" name="lng" inputmode="decimal" placeholder="121.0" aria-label="Longitude"></div></div>
      <button class="p-btn p-btn-primary p-btn-sm" type="submit"><?= e(t('Score it', 'Markahan')) ?></button>
    </div>
    <?php if (is_array($try)): ?>
      <div class="ss-tryout"><p><b><?= e($lvl[$try['level'] ?? ''] ?? (string) ($try['level'] ?? '')) ?></b> · <?= (int) ($try['score'] ?? 0) ?>/100</p>
        <ul class="ss-reasons"><?php foreach ((array) ($try['reasons'] ?? []) as $rs): ?><li><span><?= e((string) ($rs['detail'] ?? $rs['factor'] ?? '')) ?></span><b>+<?= (int) ($rs['points'] ?? 0) ?></b></li><?php endforeach; ?></ul></div>
    <?php endif; ?>
  </form>

  <?php if ($cal || $fac): ?>
  <div class="ss-two">
    <?php if ($cal): ?><section class="p-card p-card-pad"><p class="p-eyebrow"><?= e(t('How the levels are doing (90 days)', 'Kumusta ang mga antas (90 araw)')) ?></p>
      <table class="ss-table"><thead><tr><th><?= e(t('Level', 'Antas')) ?></th><th class="n"><?= e(t('Reports', 'Ulat')) ?></th><th class="n"><?= e(t('Raised', 'Itinaas')) ?></th><th class="n"><?= e(t('Lowered', 'Ibinaba')) ?></th><th class="n"><?= e(t('To dispatch (min)', 'Hanggang dispatch (min)')) ?></th></tr></thead><tbody>
      <?php foreach ($cal as $c): ?><tr><td><?= e($lvl[$c['level']] ?? (string) $c['level']) ?></td><td class="n"><?= (int) $c['reports'] ?></td><td class="n"><?= (int) $c['raised'] ?></td><td class="n"><?= (int) $c['lowered'] ?></td><td class="n"><?= $c['median_minutes_to_dispatch'] === null ? '—' : (int) round((float) $c['median_minutes_to_dispatch']) ?></td></tr><?php endforeach; ?>
      </tbody></table>
      <p class="p-hint"><?= e(t('If administrators often lower reports with a given factor, it may deserve fewer points.', 'Kung madalas ibaba ng mga administrator ang mga ulat na may isang salik, maaaring bawasan ang puntos nito.')) ?></p></section><?php endif; ?>
    <?php if ($fac): ?><section class="p-card p-card-pad"><p class="p-eyebrow"><?= e(t('Factors administrators change', 'Mga salik na binabago ng administrator')) ?></p>
      <table class="ss-table"><thead><tr><th><?= e(t('Factor', 'Salik')) ?></th><th class="n"><?= e(t('Reports', 'Ulat')) ?></th><th class="n"><?= e(t('Raised', 'Itinaas')) ?></th><th class="n"><?= e(t('Lowered', 'Ibinaba')) ?></th></tr></thead><tbody>
      <?php foreach ($fac as $f): ?><tr><td><?= e(trim((string) $f['factor'] . ' ' . (string) ($f['detail'] ?? ''))) ?></td><td class="n"><?= (int) $f['reports'] ?></td><td class="n"><?= (int) $f['raised'] ?></td><td class="n"><?= (int) $f['lowered'] ?></td></tr><?php endforeach; ?>
      </tbody></table></section><?php endif; ?>
  </div>
  <?php endif; ?>
  <?php endif; ?>
</section>

<section class="st-pane" data-pane="look" hidden>
  <div class="p-card p-card-pad st-look">
    <p class="p-eyebrow"><?= e(t('Theme and language', 'Tema at wika')) ?></p>
    <div class="st-prefs">
      <div class="st-pref"><span class="st-pref-l"><?= p_icon('i-moon', 18) ?><b><?= e(t('Theme', 'Tema')) ?></b></span>
        <div class="p-seg-mini" id="st-theme" role="group" aria-label="<?= e(t('Theme', 'Tema')) ?>">
          <button type="button" data-set-theme="light"><?= e(t('Light', 'Maliwanag')) ?></button>
          <button type="button" data-set-theme="dark"><?= e(t('Dark', 'Madilim')) ?></button>
        </div></div>
      <div class="st-pref"><span class="st-pref-l"><?= p_icon('i-dash', 18) ?><b><?= e(t('Sidebar', 'Gilid na menu')) ?></b></span>
        <div class="p-seg-mini" id="st-side" role="group" aria-label="<?= e(t('Sidebar', 'Gilid na menu')) ?>">
          <button type="button" data-mode="handle" title="<?= e(t('A small handle on its edge shrinks it to icons and back', 'Isang maliit na hawakan sa gilid ang magpapaliit nito at magbabalik')) ?>"><?= e(t('Handle', 'Hawakan')) ?></button>
          <button type="button" data-mode="hover" title="<?= e(t('Icons only; it opens when you point at it', 'Mga icon lang; bumubukas kapag tinuro mo')) ?>"><?= e(t('Hover rail', 'Riles na bumubukas')) ?></button>
        </div></div>
      <div class="st-pref"><span class="st-pref-l"><?= p_icon('i-flag', 18) ?><b><?= e(t('Language', 'Wika')) ?></b></span>
        <div class="p-seg-mini pref-lang" role="group" aria-label="<?= e(t('Language', 'Wika')) ?>">
          <button type="button" data-lang="en" aria-pressed="<?= lang() === 'en' ? 'true' : 'false' ?>" class="<?= lang() === 'en' ? 'p-on' : '' ?>"><?= lang_flag('us') ?><span>English</span></button>
          <button type="button" data-lang="fil" aria-pressed="<?= lang() === 'en' ? 'false' : 'true' ?>" class="<?= lang() === 'en' ? '' : 'p-on' ?>"><?= lang_flag('ph') ?><span>Tagalog</span></button>
        </div></div>
    </div>
  </div>
  <div class="p-card p-card-pad st-look">
    <p class="p-eyebrow"><?= e(t('Map surfaces', 'Ibabaw ng mapa')) ?></p>
    <p class="st-note" style="margin-top:0"><?= e(t('How the panels and buttons floating on the Spatial Distribution map are drawn. Glass lets the map show through; Solid is flat and plain, easier on older screens and in bright rooms. This is kept on this computer.', 'Kung paano iginuhit ang mga panel at button sa mapa. Hinahayaan ng Glass na makita ang mapa; ang Solid ay patag at simple, mas magaan sa lumang screen at sa maliwanag na silid. Nakatago ito sa computer na ito.')) ?></p>
    <div class="st-surfs" role="radiogroup" aria-label="<?= e(t('Map surfaces', 'Ibabaw ng mapa')) ?>">
      <button type="button" class="st-surf" role="radio" data-surf="glass" aria-checked="true"><span class="sv-pic g"><i></i><b></b></span><span class="ss-t"><b><?= e(t('Glass', 'Salamin')) ?></b><small><?= e(t('Frosted panels, lit edges', 'Frosted na panel, may ilaw ang gilid')) ?></small></span></button>
      <button type="button" class="st-surf" role="radio" data-surf="solid" aria-checked="false"><span class="sv-pic s"><i></i><b></b></span><span class="ss-t"><b><?= e(t('Solid', 'Buo')) ?></b><small><?= e(t('Flat graphite, no blur or gloss', 'Patag na graphite, walang blur o kinang')) ?></small></span></button>
    </div>
  </div>
<?php if (is_file(__DIR__ . '/assets/js/sd-city.js')): /* the 3D City view is parked (14 Oct): its detail setting shows only where the view exists */ ?>
  <div class="p-card p-card-pad st-look">
    <p class="p-eyebrow"><?= e(t('City view detail', 'Detalye ng City view')) ?></p>
    <p class="st-note" style="margin-top:0"><?= e(t('When you tilt the map: Full draws pitched roofs and the landmark models; Light draws plain boxes and is easier on slow screens. Auto starts with Full and drops to Light by itself if the map runs slowly. Kept on this computer.', 'Kapag ini-tilt ang mapa: ang Full ay may bubong na may anggulo at mga modelo ng landmark; ang Light ay payak na kahon at mas magaan sa mabagal na screen. Ang Auto ay nagsisimula sa Full at nagiging Light kung bumabagal ang mapa. Nakatago sa computer na ito.')) ?></p>
    <div class="st-surfs st-opts" role="radiogroup" aria-label="<?= e(t('City view detail', 'Detalye ng City view')) ?>">
      <button type="button" class="st-surf st-opt" role="radio" data-city="auto" aria-checked="true"><span class="ss-t"><b><?= e(t('Auto', 'Auto')) ?></b><small><?= e(t('Full, then Light if slow', 'Full, tapos Light kung mabagal')) ?></small></span></button>
      <button type="button" class="st-surf st-opt" role="radio" data-city="full" aria-checked="false"><span class="ss-t"><b><?= e(t('Full', 'Kumpleto')) ?></b><small><?= e(t('Pitched roofs and models', 'May bubong at modelo')) ?></small></span></button>
      <button type="button" class="st-surf st-opt" role="radio" data-city="light" aria-checked="false"><span class="ss-t"><b><?= e(t('Light', 'Magaan')) ?></b><small><?= e(t('Plain boxes', 'Payak na kahon')) ?></small></span></button>
    </div>
  </div>
<?php endif; ?>
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
  // each service's colour as an accent and a plain letter of ours; never a logo (brand rules differ)
  const ACCENT = { 'Supabase': ['S', '#3ECF8E'], 'Cloudinary': ['C', '#3448C5'], 'Render': ['R', '#6E5CF6'], 'Firebase push': ['F', '#F5A623'], 'Open-Meteo': ['O', '#2D9CDB'], 'Nominatim · OpenFreeMap': ['N', '#7EBC6F'] };
  function card(name, tier, body, catchTxt, foot) {
    const ac = ACCENT[name] || ['', '#9AA1AB'];
    return '<div class="p-card p-card-pad st-plan" style="--ac:' + ac[1] + '"><header><b><span class="st-mono" aria-hidden="true">' + ac[0] + '</span>' + esc(name) + '</b>' + (tier ? '<span class="st-tier">' + esc(tier) + '</span>' : '') + '</header>' + body +
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

  // Administrators (Jira's People page): search and position filter, position and committee save themselves
  (function () {
    const q = $('jp-q'), rs = $('jp-role'), rows = [...document.querySelectorAll('#jp-rows tr[data-name]')];
    if (!q || !rs) return;
    const apply = () => {
      const t = q.value.trim().toLowerCase(), r = rs.value; let n = 0;
      rows.forEach(tr => { const ok = (!t || tr.dataset.name.includes(t)) && (!r || tr.dataset.role === r); tr.hidden = !ok; if (ok) n++; });
      $('jp-none').hidden = n > 0;
    };
    q.addEventListener('input', apply); rs.addEventListener('change', apply);
    const add = $('jp-add'), card = $('jp-addcard');
    add.addEventListener('click', () => { card.hidden = !card.hidden; add.setAttribute('aria-expanded', String(!card.hidden)); if (!card.hidden) { card.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); const f = card.querySelector('input[name=first_name]'); if (f) f.focus(); } });
    document.querySelectorAll('.ss-jrole').forEach(f => {
      const sel = i => document.querySelector('[form="' + f.id + '"][' + i + ']'), role = sel('data-role-sel'), comm = sel('data-comm-sel');
      const go = () => { if (role.value === 'kagawad' && !comm.value) { comm.disabled = false; comm.focus(); return; } comm.disabled = role.value !== 'kagawad'; f.submit(); };
      role.addEventListener('change', () => { comm.disabled = role.value !== 'kagawad'; if (role.value !== 'kagawad') comm.value = ''; go(); });
      comm.addEventListener('change', go);
    });
  })();

  document.querySelectorAll('.st-tabs [data-st]').forEach(b => b.addEventListener('click', () => {
    document.querySelectorAll('.st-tabs [data-st]').forEach(x => x.classList.toggle('p-on', x === b));
    document.querySelectorAll('.st-pane').forEach(p => p.hidden = p.dataset.pane !== b.dataset.st);
    const live = b.dataset.st === 'status' || b.dataset.st === 'usage'; $('st-check').hidden = !live; $('st-checked').hidden = !live;
  }));
  $('st-check').addEventListener('click', () => { check(); usage(); });
  check(); usage();
})();
</script>
<script>
// Theme: Light or Dark, kept in this browser (the sidebar switch moved here, 14 Oct).
(function () {
  var wrap = document.getElementById('st-theme'); if (!wrap) return;
  var root = document.documentElement;
  function paint() { var cur = root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light'; wrap.querySelectorAll('button').forEach(function (b) { b.classList.toggle('p-on', b.dataset.setTheme === cur); b.setAttribute('aria-pressed', String(b.dataset.setTheme === cur)); }); }
  wrap.addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    root.setAttribute('data-theme', b.dataset.setTheme); root.setAttribute('data-bs-theme', b.dataset.setTheme);
    try { localStorage.setItem('ss-theme', b.dataset.setTheme); } catch (x) {}
    paint(); window.dispatchEvent(new CustomEvent('themechange', { detail: b.dataset.setTheme }));
  });
  paint();
})();
</script>
<script>
// Sidebar: a handle on its edge, or a rail that opens when you point at it; kept in this browser.
(function () {
  var wrap = document.getElementById('st-side'); if (!wrap) return;
  var root = document.documentElement;
  function mode() { try { return localStorage.getItem('ss-side-mode') === 'hover' ? 'hover' : 'handle'; } catch (e) { return 'handle'; } }
  function paint() { var m = mode(); wrap.querySelectorAll('button').forEach(function (b) { b.classList.toggle('p-on', b.dataset.mode === m); b.setAttribute('aria-pressed', String(b.dataset.mode === m)); }); }
  wrap.addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    try { localStorage.setItem('ss-side-mode', b.dataset.mode); } catch (x) {}
    var min = false; try { min = localStorage.getItem('ss-side') === 'min'; } catch (x) {}
    if (b.dataset.mode === 'hover') root.setAttribute('data-side', 'hover'); else if (min) root.setAttribute('data-side', 'min'); else root.removeAttribute('data-side');
    paint(); window.dispatchEvent(new Event('resize'));
  });
  paint();
})();
</script>
<script>
// Back on the Administrators tab after adding or resetting.
if (location.hash === '#admins' || location.hash === '#smart') { var b = document.querySelector('.st-tabs [data-st="' + location.hash.slice(1) + '"]'); if (b) b.click(); }
</script>
<script>
// Map surfaces: Glass or Solid, kept in this browser.
(function () {
  var btns = document.querySelectorAll('.st-surf'); if (!btns.length) return;
  function paint() { var solid = document.documentElement.getAttribute('data-surface') === 'solid'; btns.forEach(function (b) { b.setAttribute('aria-checked', String((b.dataset.surf === 'solid') === solid)); }); }
  btns.forEach(function (b) { b.addEventListener('click', function () {
    var solid = b.dataset.surf === 'solid';
    if (solid) document.documentElement.setAttribute('data-surface', 'solid'); else document.documentElement.removeAttribute('data-surface');
    try { localStorage.setItem('ss-surface', solid ? 'solid' : 'glass'); } catch (e) { /* kept for this visit only */ }
    paint();
  }); });
  paint();
  // City view detail
  var city = document.querySelectorAll('.st-opt'); function cur() { try { return localStorage.getItem('ss-city') || 'auto'; } catch (e) { return 'auto'; } }
  function paintCity() { var c = cur(); city.forEach(function (b) { b.setAttribute('aria-checked', String(b.dataset.city === c)); }); }
  city.forEach(function (b) { b.addEventListener('click', function () { try { localStorage.setItem('ss-city', b.dataset.city); } catch (e) { /* this visit only */ } paintCity(); }); });
  paintCity();
})();
</script>
<?php layout_foot(); ?>
