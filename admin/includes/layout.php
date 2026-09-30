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
    return [
        ['dashboard.php',  t('Dashboard', 'Dashboard'),                       'chart'],
        ['summary.php',    t('Report Summary', 'Buod ng mga Ulat'),           'doc'],
        ['spatial.php',    t('Spatial Distribution', 'Mapa ng mga Sumbong'),  'map'],
        ['cases.php',      t('Case Reports', 'Mga Sumbong'),                  'chat'],
        ['residents.php',  t('Residents', 'Mga Residente'),                   'users'],
        ['personnel.php',  t('Personnel', 'Mga Tanod'),                       'user'],
        ['retirement-requests.php', t('Extra Administrative Services', 'Iba pang Serbisyong Pang-admin'), 'badge'],
        ['profile.php',    t('Edit Profile', 'I-edit ang Profile'),           'gear'],
    ];
}

function nav_icon(string $name): string
{
    $paths = [
        'chart' => '<path d="M3 3v18h18"/><rect x="7" y="10" width="3" height="7"/><rect x="12" y="6" width="3" height="11"/><rect x="17" y="13" width="3" height="4"/>',
        'doc'   => '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/>',
        'map'   => '<polygon points="1 6 8 3 16 6 23 3 23 18 16 21 8 18 1 21"/><line x1="8" y1="3" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="21"/>',
        'chat'  => '<path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 8.5 8.5 0 0 1-3.8-.9L3 21l1.9-5.2A8.4 8.4 0 0 1 12 3a8.4 8.4 0 0 1 9 8.5z"/>',
        'users' => '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.9"/>',
        'user'  => '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
        'badge' => '<circle cx="12" cy="8" r="6"/><path d="M8.5 13.5 7 22l5-3 5 3-1.5-8.5"/>',
        'gear'  => '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2 2 2 0 1 1-4 0 1.7 1.7 0 0 0-2.9-1.2l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.7 1.7 0 0 0 3 15a2 2 0 1 1 0-4 1.7 1.7 0 0 0 1.5-2.6l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.7 1.7 0 0 0 10 4.6a2 2 0 1 1 4 0 1.7 1.7 0 0 0 2.9 1.2l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1A1.7 1.7 0 0 0 21 11a2 2 0 1 1 0 4z"/>',
        'out'   => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
        'search'=> '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>',
    ];
    $d = $paths[$name] ?? '';
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
         . 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . $d . '</svg>';
}

function layout_head(string $title, string $active = ''): void
{
    $admin = current_admin();
    ?><!DOCTYPE html>
<html lang="<?= html_lang() ?>">
<head>
<meta charset="utf-8">
<?= theme_head() ?>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>
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
<title><?= e($title) ?> — Smart Sumbong | Barangay 183</title>
<link rel="icon" type="image/png" href="assets/img/brgy-183-seal.png">
<link rel="apple-touch-icon" href="assets/img/brgy-183-seal.png">
<meta name="theme-color" content="#0B2B6B">
<link href="assets/vendor/bootstrap/bootstrap.min.css" rel="stylesheet">
<link href="assets/css/fonts.css?v=<?= e(asset_version('fonts.css')) ?>" rel="stylesheet">
<link href="assets/css/app.css?v=<?= e(asset_version('app.css')) ?>" rel="stylesheet">
</head>
<body class="page-<?= e(basename($active, '.php')) ?>">
<div class="shell">
  <nav class="sidebar">
    <a class="brand" href="dashboard.php">
      <?php if (is_file(__DIR__ . '/../assets/img/logo-wordmark.png')): ?>
        <img src="assets/img/logo-wordmark.png" alt="Smart Sumbong">
      <?php else: ?>
        <div class="brand-fallback">Sm<span>art</span>Sumbong</div>
      <?php endif; ?>
    </a>

    <?php $live = open_complaint_count(); ?>
    <?php foreach (nav_items() as [$href, $label, $icon]): ?>
      <?php $pulse = ($icon === 'map' && $live > 0); ?>
      <a class="nav-item<?= basename($href) === $active ? ' active' : '' ?>" href="<?= e($href) ?>">
        <?php if ($pulse): ?>
          <span class="nav-pulse is-live" title="<?= e($live . ' ' . t($live === 1 ? 'open complaint' : 'open complaints', 'bukas na sumbong')) ?>">
            <?= nav_icon($icon) ?><span class="nav-num"><?= $live > 99 ? '99+' : $live ?></span>
          </span>
        <?php else: ?>
          <?= nav_icon($icon) ?>
        <?php endif; ?>
        <span><?= e($label) ?></span>
      </a>
    <?php endforeach; ?>

    <div class="nav-spacer"></div>

    <?= prefs_switches('prefs--sidebar') ?>

    <a class="nav-item" href="logout.php"><?= nav_icon('out') ?><span><?= e(t('Log out', 'Mag-log out')) ?></span></a>
  </nav>

  <main class="main">
<?php
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
    <div class="idle-veil" id="idle-veil" hidden>
      <div class="idle-box" role="alertdialog" aria-labelledby="idle-h" aria-describedby="idle-p">
        <h2 id="idle-h"><?= e(t('Still there?', 'Nandiyan ka pa ba?')) ?></h2>
        <p id="idle-p">
          <?= e(t("You have been idle for a while. For the barangay's security this session will end in",
                  'Matagal ka nang walang galaw. Para sa seguridad ng barangay, matatapos ang session na ito sa')) ?>
          <strong id="idle-left">120</strong> <?= e(t('seconds.', 'segundo.')) ?>
        </p>
        <div class="confirm-actions">
          <button class="btn-accept" type="button" id="idle-stay"><?= e(t('Keep me signed in', 'Manatiling naka-sign in')) ?></button>
          <button class="btn-deny" type="button" id="idle-go"><?= e(t('Sign out now', 'Mag-sign out ngayon')) ?></button>
        </div>
      </div>
    </div>

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
        veil.removeAttribute('hidden');
        graceTimer = setInterval(function () {
          left.textContent = --remaining;
          if (remaining <= 0) { clearInterval(graceTimer); signOut(); }
        }, 1000);
      }

      function reset() {
        if (!veil.hasAttribute('hidden')) return;   // the prompt is up; ignore stray events
        clearTimeout(idleTimer);
        idleTimer = setTimeout(warn, IDLE_MS);
      }

      document.getElementById('idle-stay').addEventListener('click', function () {
        clearInterval(graceTimer);
        veil.setAttribute('hidden', '');
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
function open_complaint_count(): int
{
    static $n = null;
    if ($n !== null) return $n;

    try {
        $n = db()->count('reports', [
            'deleted_at' => 'is.null',
            'status'     => 'in.(pending_review,validated,assigned,in_progress,offline_investigation)',
        ]);
    } catch (Throwable) {
        $n = 0;
    }
    return $n;
}

function layout_foot(): void
{
    ?>
  </main>
</div>
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
    return [
        'VAWC Desk'                  => t('VAWC Desk (violence against women and children)', 'VAWC Desk (karahasan sa kababaihan at bata)'),
        'Philippine National Police' => t('Philippine National Police (PNP)', 'Philippine National Police (PNP)'),
        'City Social Welfare Office' => t('City Social Welfare Office (DSWD)', 'City Social Welfare Office (DSWD)'),
        'Lupong Tagapamayapa'        => t('Lupong Tagapamayapa (Katarungang Pambarangay)', 'Lupong Tagapamayapa (Katarungang Pambarangay)'),
        'City Environment Office'    => t('City Environment Office (ENRO)', 'City Environment Office (ENRO)'),
        'Bureau of Fire Protection'  => t('Bureau of Fire Protection (BFP)', 'Bureau of Fire Protection (BFP)'),
        'City Health Office'         => t('City Health Office', 'City Health Office'),
        // With the Certification of Lack of Jurisdiction's own reasons.
        'Office of the Ombudsman'    => t('Office of the Ombudsman (a public officer, in official duties)', 'Office of the Ombudsman (pampublikong opisyal, sa tungkulin)'),
        'Regular Courts'             => t('Regular courts (parties live in different cities)', 'Regular na hukuman (magkaibang lungsod ang tirahan)'),
    ];
}

function office_picker(string $id, ?string $suggested = null): void
{
    $offices = escalation_offices();
    ?>
    <div class="control-field">
      <label class="field-label" for="<?= e($id) ?>"><?= e(t('Escalate to', 'I-escalate sa')) ?></label>
      <select id="<?= e($id) ?>" name="agency" required data-office>
        <option value=""><?= e(t('Choose an office', 'Pumili ng tanggapan')) ?></option>
        <?php foreach ($offices as $val => $lbl): ?>
          <option value="<?= e($val) ?>" <?= $suggested === $val ? 'selected' : '' ?>><?= e($lbl) ?></option>
        <?php endforeach; ?>
        <option value="other"><?= e(t('Another office…', 'Ibang tanggapan…')) ?></option>
      </select>
    </div>
    <div class="control-field" data-office-other hidden>
      <label class="field-label" for="<?= e($id) ?>-other"><?= e(t('Name of the office', 'Pangalan ng tanggapan')) ?></label>
      <input type="text" id="<?= e($id) ?>-other" name="agency_other" maxlength="120">
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

function status_class(string $s): string
{
    return match ($s) {
        'pending_review'        => 'pending',
        'validated'             => 'validated',
        'assigned'              => 'assigned',
        'in_progress',
        'offline_investigation' => 'progress',
        'resolved'              => 'resolved',
        'closed', 'archived'    => 'closed',
        'rejected'              => 'rejected',
        default                 => 'pending',
    };
}

function category_label(string $c): string
{
    return ucwords(str_replace('_', ' ', $c));
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
                 . substr(sha1($msg), 0, 8)
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
