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
        ['dashboard.php',  'Dashboard',           'chart'],
        ['summary.php',    'Report Summary',      'doc'],
        ['spatial.php',    'Spatial Distribution','map'],
        ['cases.php',      'Case Reports',        'chat'],
        ['residents.php',  'Residents',           'users'],
        ['personnel.php',  'Personnel',           'user'],
        ['profile.php',    'Edit Profile',        'gear'],
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
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($title) ?> — Smart Sumbong | Barangay 183</title>
<link rel="icon" type="image/png" href="assets/img/brgy-183-seal.png">
<link rel="apple-touch-icon" href="assets/img/brgy-183-seal.png">
<meta name="theme-color" content="#0B2B6B">
<link href="assets/vendor/bootstrap/bootstrap.min.css" rel="stylesheet">
<link href="assets/css/fonts.css" rel="stylesheet">
<link href="assets/css/app.css" rel="stylesheet">
</head>
<body>
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
          <span class="nav-pulse is-live" title="<?= $live ?> open complaint<?= $live === 1 ? '' : 's' ?>">
            <?= nav_icon($icon) ?><span class="nav-num"><?= $live > 99 ? '99+' : $live ?></span>
          </span>
        <?php else: ?>
          <?= nav_icon($icon) ?>
        <?php endif; ?>
        <span><?= e($label) ?></span>
      </a>
    <?php endforeach; ?>

    <div class="nav-spacer"></div>

    <a class="nav-item" href="logout.php"><?= nav_icon('out') ?><span>Log out</span></a>
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
        <h2 id="idle-h">Still there?</h2>
        <p id="idle-p">
          You have been idle for a while. For the barangay's security this
          session will end in <strong id="idle-left">120</strong> seconds.
        </p>
        <div class="confirm-actions">
          <button class="btn-accept" type="button" id="idle-stay">Keep me signed in</button>
          <button class="btn-deny" type="button" id="idle-go">Sign out now</button>
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
</body>
</html>
<?php
}

/** Human labels for the enum values the database stores. */
function status_label(string $s): string
{
    return ucwords(str_replace('_', ' ', $s));
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
    $old = $log['old_status'] ?? null;
    $new = $log['new_status'] ?? '';

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
        return 'Complaint Filed';
    }
    if ($old === null || $old === $new) {
        return 'Case updated';
    }
    return match ($new) {
        'validated'  => 'Complaint Accepted',
        'rejected'   => 'Complaint Denied',
        'assigned'   => 'Tanod Assigned',
        'in_progress'=> 'Response Underway',
        'resolved'   => 'Marked Resolved',
        'closed'     => 'Case Closed',
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
            return 'That action could not be completed. Reference: ' . substr(sha1($msg), 0, 8)
                 . ' — give this to whoever maintains the system.';
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
    if ($mins < 1)    return 'Just now';
    if ($mins < 60)   return "{$mins} min ago";
    if ($mins < 1440) return floor($mins / 60) . ' hr ago';
    return $then->setTimezone(new DateTimeZone('Asia/Manila'))->format('M j \a\t g:i A');
}
