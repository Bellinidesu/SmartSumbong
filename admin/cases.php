<?php
/**
 * Case Reports — Figma node 2:2230.
 *
 * Two stacked panels: unread notifications across the top, then the
 * complaint register. Both read through PostgREST with the signed-in
 * admin's token, so the rows that come back are the rows their RLS
 * policies allow. Nothing here filters by role in PHP.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/briefing.php';
require_once __DIR__ . '/includes/board.php';
require_once __DIR__ . '/includes/widget_panel.php';

$admin = require_admin();
$db    = db();

session_start_once();

// Notifications: mark one as read (also by beacon when its action is followed), or all of them.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && defined('NOTICES_PAGE') && !defined('WORKSPACE_PAGE') && in_array($_POST['action'] ?? '', ['read_one', 'read_all'], true)) {
    if (csrf_check($_POST['csrf'] ?? null)) {
        try {
            $rq = ['user_id' => 'eq.' . $admin['id'], 'is_read' => 'is.false'];
            if ($_POST['action'] === 'read_one') {
                $nid = (string) ($_POST['id'] ?? '');
                if (preg_match('/^[0-9a-f-]{36}$/i', $nid)) { $rq['id'] = 'eq.' . $nid; $db->update('notifications', $rq, ['is_read' => true]); }
            } else {
                $db->update('notifications', $rq, ['is_read' => true]);
            }
            unset($_SESSION['nav_counts']);     // the sidebar's number follows at once
        } catch (SupabaseError) { /* the list will still show it */ }
    }
    if (!empty($_POST['beacon'])) { http_response_code(204); exit; }
    header('Location: notifications.php' . (!empty($_POST['back']) ? '?' . http_build_query(['npage' => (int) $_POST['back']]) : ''), true, 303);
    exit;
}

// Coming back from a case should land on the list you left, not on an
// unfiltered one you have to rebuild. Any explicit parameter wins; a bare
// visit restores what you last looked at.
// Only the register remembers its view. Notifications and Workspace load this same file, and a remembered
// "tab" sent a bare click on Case Reports or Notifications to the wrong page (15 Oct 2026).
$registerPage = !defined('NOTICES_PAGE') && !defined('WORKSPACE_PAGE');
if ($registerPage && !isset($_GET['q'], $_GET['status'], $_GET['sort'], $_GET['month'], $_GET['category'])
    && ($_SERVER['QUERY_STRING'] ?? '') === '' && !empty($_SESSION['cases_view'])) {
    $_GET = array_diff_key($_SESSION['cases_view'], ['tab' => 1, 'stage' => 1]) + $_GET;
}

// The seven categories are fixed per the Scope and Limitations — the same
// list cases.php's category dropdown and the resident app's own filing
// form both draw from.
const CATEGORIES = [
    'street_obstruction', 'public_safety_infrastructure', 'environmental_waste_hazard',
    'animal_welfare', 'traffic_violation', 'barangay_service', 'peace_order_nuisance', 'other',
];

// Rose's feedback (Sep 2026): stick to four buckets an admin actually
// scans for — Under Review, In Progress, Rejected, Resolved/Completed —
// rather than the raw 8-value enum. Same grouping spatial.php's map
// filter already adopted (15 Sep 2026); this just brings the list view
// to the same simplification, the full breakdown stays one click away
// on each case's own detail page.
const STATUS_GROUPS = [
    'under_review' => ['pending_review', 'validated'],
    'in_progress'  => ['assigned', 'in_progress', 'offline_investigation'],
    'resolved'     => ['resolved', 'closed', 'archived'],
    'rejected'     => ['rejected'],
];

$search   = trim((string) ($_GET['q'] ?? ''));
$filter   = (string) ($_GET['status'] ?? '');
$category = (string) ($_GET['category'] ?? '');
$month    = (string) ($_GET['month'] ?? '');
$view     = (string) ($_GET['view'] ?? '');
// 0087: whose cases — mine, unclaimed, or other admins'.
// Rose (7 Oct): filter by who handles the case — nobody yet, or an admin.
$who      = (string) ($_GET['who'] ?? '');
if ($who !== '' && $who !== 'unclaimed' && !preg_match('/^[0-9a-f-]{36}$/i', $who)) { $who = ''; }
// Defense, 7 Sep: the panel asked for pages ("paginated, no scroll scroll") and for Case Reports to hold
// real cases only, with the notifications on their own. Three tabs: Next up (the SMART queue, 0129),
// All cases (the register) and Notifications. PER_PAGE rows a page everywhere.
const PER_PAGE = 15;
const QUEUE_STAGES = ['review', 'dispatch', 'accept', 'reply', 'approve', 'escalation', 'follow_up'];
// Case Reports is the register of real cases. What needs doing and the notifications live on notifications.php,
// which loads this same file (NOTICES_PAGE) so the two share one query and one live refresh.
$workspace = defined('WORKSPACE_PAGE');     // the work board has its own page (workspace.php)
$notices   = defined('NOTICES_PAGE') || $workspace;
$tab   = (string) ($_GET['tab'] ?? '');
if ($workspace) {
    $tab = 'next';
} elseif ($notices) {
    if ($tab === 'next') {                       // an old link to the board
        $q = $_GET; unset($q['tab']);
        header('Location: workspace.php' . ($q ? '?' . http_build_query($q) : ''), true, 302);
        exit;
    }
    $tab = 'notes';
} else {
    if ($tab === 'next' || $tab === 'notes') {   // an old link or bookmark
        $q = $_GET; unset($q['tab']);
        header('Location: ' . ($tab === 'next' ? 'workspace.php' : 'notifications.php') . ($q ? '?' . http_build_query($q) : ''), true, 302);
        exit;
    }
    $tab = 'all';
}
$page  = max(1, (int) ($_GET['page'] ?? 1));
$npage = max(1, (int) ($_GET['npage'] ?? 1));
$stage = (string) ($_GET['stage'] ?? '');
if (!in_array($stage, QUEUE_STAGES, true)) { $stage = ''; }
// Panel (5 Sep): the case list should be able to show only what the tanod is doing: cases waiting for a tanod, and cases a tanod has.
$tanod = (string) ($_GET['tanod'] ?? '');
if (!in_array($tanod, ['needs', 'active'], true)) { $tanod = ''; }
// The Notification panel's own search and order (Rose, 27 Sep 2026: both
// were only drawn, never read).
$nSearch  = trim((string) ($_GET['nq'] ?? ''));
$nAll     = ($_GET['nview'] ?? '') === 'all';   // Unread (the default) or everything, read ones too
$nSort    = ($_GET['nsort'] ?? 'newest') === 'oldest' ? 'oldest' : 'newest';

if (!in_array($category, CATEGORIES, true)) { $category = ''; }
if (!preg_match('/^\d{4}-\d{2}$/', $month)) { $month = ''; }
// Rose (7 Oct 2026): Overdue and Escalated sit in the same Status menu.
const OPEN_STATES = ['pending_review', 'validated', 'assigned', 'in_progress', 'offline_investigation'];
if (!isset(STATUS_GROUPS[$filter]) && !in_array($filter, ['overdue', 'escalated', 'with_kagawad', 'with_chairman'], true)) { $filter = ''; }

// Clicking a column heading sorts by it; clicking the same one again
// reverses. PostgREST cannot order by an embedded resident name, so that
// column is not offered as a sort.
$SORTABLE = ['id' => 'tracking_id', 'category' => 'category', 'status' => 'status', 'date' => 'created_at'];
$sortCol  = $_GET['by'] ?? 'date';
$sortDir  = ($_GET['dir'] ?? 'desc') === 'asc' ? 'asc' : 'desc';
if (!isset($SORTABLE[$sortCol])) { $sortCol = 'date'; }
$sort = $SORTABLE[$sortCol] . '.' . $sortDir;

if ($registerPage) {
    $_SESSION['cases_view'] = array_filter([
        'q' => $search, 'status' => $filter, 'category' => $category, 'month' => $month, 'view' => $view,
        'by' => $sortCol, 'dir' => $sortDir, 'tanod' => $tanod,
    ], fn($v) => $v !== '');
}

/** Link for a column heading, flipping direction if it is the active one. */
function sort_link(string $col, string $active, string $dir): string
{
    $next = ($col === $active && $dir === 'asc') ? 'desc' : 'asc';
    $q = $_GET;
    $q['by'] = $col; $q['dir'] = $next;
    return '?' . http_build_query($q);
}
function sort_caret(string $col, string $active, string $dir): string
{
    return $col === $active ? ($dir === 'asc' ? ' ▲' : ' ▼') : '';
}

$error = null;
$reports = [];
$notifications = [];
$escalations = [];
$adminList = [];

try {
    // The embedded resident is a PostgREST foreign-key expansion; the
    // join happens in the database, not in a second round trip.
    $query = [
        'select' => 'id,tracking_id,subject,category,status,created_at,is_anonymous,location_label,'
                  . 'due_at,awaiting_unit_since,reopened_count,appealed_at,referred_to,higher_official,followed_up_at,resolution_submitted_at,'
                  . 'resident:users!reports_resident_id_fkey(full_name),'
                  . 'handler_id,handler:users!reports_handler_id_fkey(full_name,official_role),'
                  . 'triage:report_triage(score,effective_level,override_level,possible_duplicates)',
        'deleted_at' => 'is.null',
        'order'      => $sort,
        'limit'      => (string) ($view === 'attention' ? 500 : PER_PAGE),
        'offset'     => (string) ($view === 'attention' ? 0 : ($page - 1) * PER_PAGE),
    ];
    $and = [];
    if ($filter === 'overdue') {
        $query['status'] = 'in.(' . implode(',', OPEN_STATES) . ')';
        $query['due_at'] = 'lt.' . gmdate('Y-m-d\TH:i:s\Z');
    } elseif ($filter === 'escalated') {
        // To an outside office, or handed up to a higher official inside the barangay.
        $and[] = 'or(referred_to.not.is.null,higher_official.not.is.null)';
    } elseif ($filter === 'with_kagawad' || $filter === 'with_chairman') {
        // 0130: where the case sits on the ladder inside the barangay.
        $query['tier'] = 'eq.' . ($filter === 'with_kagawad' ? 1 : 2);
    } elseif ($filter !== '') {
        $query['status'] = 'in.(' . implode(',', STATUS_GROUPS[$filter]) . ')';
    }
    if ($tanod === 'needs') {
        $and[] = 'status.in.(validated)';
    } elseif ($tanod === 'active') {
        $and[] = 'status.in.(assigned,in_progress,offline_investigation)';
    }
    if ($who === 'unclaimed') {
        $query['handler_id'] = 'is.null';
    } elseif ($who !== '') {
        $query['handler_id'] = 'eq.' . $who;
    }
    if ($category !== '') {
        $query['category'] = 'eq.' . $category;
    }
    if ($month !== '') {
        $mtz   = new DateTimeZone('Asia/Manila');
        $start = DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', $mtz);
        $end   = $start->modify('first day of next month');
        $and[] = "created_at.gte.{$start->format(DateTimeInterface::ATOM)}";
        $and[] = "created_at.lt.{$end->format(DateTimeInterface::ATOM)}";
    }
    if ($and) {
        $query['and'] = '(' . implode(',', $and) . ')';
    }
    if ($search !== '') {
        // Match either the tracking id or the subject line. Commas,
        // parentheses, quotes, backslashes and * are PostgREST's own
        // or=() syntax; left in, a search like "poste (ilaw)" failed to
        // parse and the whole list came back as a reference-code error.
        $needle = preg_replace('/[,()"\\\\*]/', ' ', $search);
        $query['or'] = "(tracking_id.ilike.*{$needle}*,subject.ilike.*{$needle}*)";
    }
    // Built now, fetched below together with notifications, escalations
    // and the admin list: one round trip instead of four (speed, 7 Oct).


    // Unread by default; a search looks through read ones too, since
    // what an admin searches for is usually something already seen.
    $nq = [
        'select'  => 'id,kind,message,created_at,is_read,report_id,subject_user_id,subject:users!notifications_subject_user_id_fkey(role)',
        'user_id' => 'eq.' . $admin['id'],
        'order'   => 'created_at.' . ($nSort === 'oldest' ? 'asc' : 'desc'),
        'limit'   => '20',
    ];
    // The engine's recurring, spike and quiet-case notes are the "Right now" cards above the list: never listed twice.
    $nq['and'] = '(message.not.like.SMART: recurring*,message.not.like.SMART: spike*,message.not.like.SMART:*has had no update for*)';
    if ($nSearch !== '') {
        $nq['message'] = 'ilike.*' . preg_replace('/[,()"\\\\*]/', ' ', $nSearch) . '*';
    }
    if ($nSearch === '' && !$nAll) {
        $nq['is_read'] = 'is.false';
    }
    $selects = [
        'notes_n' => ['notifications', ['user_id' => 'eq.' . $admin['id'], 'is_read' => 'is.false', 'and' => '(message.not.like.SMART: recurring*,message.not.like.SMART: spike*,message.not.like.SMART:*has had no update for*)']],
        'esc_n'   => ['escalation_requests', ['status' => 'eq.pending']],
    ];
    $counts = $db->selectMany($selects, true);
    $notesUnread = $counts['notes_n'] instanceof SupabaseError ? 0 : (int) $counts['notes_n'];
    $escCount    = $counts['esc_n'] instanceof SupabaseError ? 0 : (int) $counts['esc_n'];

    $sel = [];
    if ($tab === 'all') {
        $sel['reports'] = ['reports', $query];
        $sel['admins']  = ['users', ['select' => 'id,full_name', 'role' => 'eq.admin', 'order' => 'full_name.asc'], true];
        // the chip counts what needs attention across ALL open cases, not only this page
        $sel['open']    = ['reports', ['select' => 'status,due_at,followed_up_at,resolution_submitted_at,awaiting_unit_since,handler_id', 'deleted_at' => 'is.null',
                                       'status' => 'in.(' . implode(',', OPEN_STATES) . ')', 'limit' => '500'], true];
    } elseif ($tab === 'notes') {
        $nq['limit']  = (string) PER_PAGE;
        $nq['offset'] = (string) (($npage - 1) * PER_PAGE);
        $sel['notes'] = ['notifications', $nq];
        // 0073 — Manage Escalation Request: tanods' requests waiting on an admin.
        $sel['escalations'] = ['escalation_requests', [
            'select' => 'id,reason,suggested_office,created_at,'
                      . 'report:reports!escalation_requests_report_id_fkey(id,tracking_id,category),'
                      . 'requester:users!escalation_requests_requested_by_fkey(full_name)',
            'status' => 'eq.pending',
            'order'  => 'created_at.asc',
        ], true];
    }
    $got = $sel ? $db->selectMany($sel) : [];
    $reports       = $got['reports'] ?? [];
    $notifications = $got['notes'] ?? [];
    $escalations   = ($got['escalations'] ?? []) instanceof SupabaseError ? [] : ($got['escalations'] ?? []);
    $adminList     = ($got['admins'] ?? []) instanceof SupabaseError ? [] : ($got['admins'] ?? []);
    $openRows      = ($got['open'] ?? []) instanceof SupabaseError ? [] : ($got['open'] ?? []);

    // the total behind the pages (the register by its filters, notifications by their search)
    $regTotal = 0; $notesTotal = 0;
    if ($tab === 'all') {
        $cq = $query; unset($cq['select'], $cq['order'], $cq['limit'], $cq['offset']);
        $regTotal = $view === 'attention' ? 0 : $db->count('reports', $cq);
    } elseif ($tab === 'notes') {
        $ncq = $nq; unset($ncq['select'], $ncq['order'], $ncq['limit'], $ncq['offset']);
        $notesTotal = $db->count('notifications', $ncq);
    }

    // The SMART queue (0129): every open case by priority with its next action. Failure here must not break the page.
    $queue = []; $queueStages = array_fill_keys(QUEUE_STAGES, 0); $queueErr = false;
    if ($tab === 'next') {
        try {
            $all = $db->rpc('smart_queue', ['p_stage' => null, 'p_limit' => 500]);
            $all = is_array($all) ? $all : [];
            foreach ($all as $q) { if (isset($queueStages[$q['stage']])) { $queueStages[$q['stage']]++; } }
            $queue = $stage === '' ? $all : array_values(array_filter($all, fn($q) => $q['stage'] === $stage));
        } catch (SupabaseError $qe) { $queueErr = true; }
    }
    // The work board (Ace's pick): who has each case, and what this person is meant to see first.
    $bmeta = ['owners' => [], 'committee' => [], 'me' => ['official_role' => null, 'committee' => null]]; $bscope = 'all'; $bcount = ['mine' => 0, 'free' => 0, 'all' => 0];
    if ($tab === 'next' && $notices) {
        $bmeta  = board_data($db, $queue, $admin);
        $bscope = (string) ($_GET['own'] ?? (in_array($bmeta['me']['official_role'], ['kagawad', 'chairman'], true) ? 'mine' : 'all'));
        if (!in_array($bscope, ['mine', 'free', 'all'], true)) { $bscope = 'all'; }
        foreach (array_keys($bcount) as $sc) { $bcount[$sc] = count(array_filter($queue, fn($q) => board_visible($q, $bmeta, $admin, $sc))); }
    }

    // "Needs attention" is the question an admin actually opens this page
    // with: what is late, what nobody has picked up, and what is still
    // sitting unreviewed. Three separate conditions, one chip.
    $attention = array_values(array_filter($tab === 'all' ? $openRows : [], function (array $r) {
        $open    = !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true);
        $overdue = $open && !empty($r['due_at']) && strtotime($r['due_at']) < time();
        return $overdue
            || ($open && !empty($r['followed_up_at']))   // 0072: the resident asked again
            || !empty($r['resolution_submitted_at'])      // 0073: waiting for approval
            || !empty($r['awaiting_unit_since'])
            || $r['status'] === 'pending_review';
    }));
    if ($view === 'attention' && $tab === 'all') {
        $att = array_values(array_filter($reports, function (array $r) {
            $open = !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true);
            return ($open && !empty($r['due_at']) && strtotime($r['due_at']) < time())
                || ($open && !empty($r['followed_up_at'])) || !empty($r['resolution_submitted_at'])
                || !empty($r['awaiting_unit_since']) || $r['status'] === 'pending_review';
        }));
        $regTotal = count($att);
        $reports  = array_slice($att, ($page - 1) * PER_PAGE, PER_PAGE);
    }

} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

layout_head($workspace ? t('Workspace', 'Tablero ng Gawain') : ($notices ? t('Notifications', 'Mga Abiso') : t('Case Reports', 'Mga Sumbong')),
            $workspace ? 'workspace.php' : ($notices ? 'notifications.php' : 'cases.php'));
?>

<div class="p-topbar"><h1><?= $workspace ? e(t('Workspace', 'Tablero ng Gawain')) : ($notices ? e(t('Notifications', 'Mga Abiso')) : e(t('Case Reports', 'Mga Sumbong'))) ?></h1>
  <span class="p-live" id="live-badge" title="<?= e(t('Updates as they happen — no reload needed', 'Nag-a-update habang nangyayari — hindi na kailangang i-reload')) ?>"><i></i><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span></span></div>

<?php if ($error): ?>
  <div class="p-flash p-flash--error" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<?php
// Both forms carry the Reports panel's filters along, so searching
// notifications does not reset the list below.
$keep = array_filter(['tab' => $tab, 'q' => $search, 'status' => $filter, 'category' => $category, 'tanod' => $tanod,
                      'month' => $month, 'view' => $view, 'by' => $sortCol, 'dir' => $sortDir],
                     fn($v) => $v !== '');
?>
<?php
$tabHref = fn(string $t) => '?' . http_build_query(['tab' => $t]);
$noteBadge = $notesUnread + $escCount;
?>
<?php if ($notices) { render_briefing($db, $admin, $workspace ? 'bar' : 'strip'); } ?>
<?php if ($workspace) { render_widget_panel($db, $admin); } ?>
<?php if (false): ?>
<nav class="ss-tabs" aria-label="<?= e(t('Notifications views', 'Mga tanaw ng Abiso')) ?>">
  <a href="<?= e($tabHref('next')) ?>"<?= $tab === 'next' ? ' class="on" aria-current="page"' : '' ?>><?= e(t('Board', 'Tablero')) ?></a>
  <a href="<?= e($tabHref('notes')) ?>"<?= $tab === 'notes' ? ' class="on" aria-current="page"' : '' ?>><?= e(t('All notifications', 'Lahat ng abiso')) ?><?php if ($noteBadge > 0): ?> <span class="p-badge-n" id="tab-notes-n"><?= $noteBadge ?></span><?php endif; ?></a>
</nav>
<?php endif; ?>

<?php if ($tab === 'next'): ?>
<!-- ---------- the work board (0129 queue, one column per stage) ---------- -->
<div class="bd-bar">
  <div class="bd-ttl"><span class="p-sub"><?= e(t('Drag a card to another stage: the real action opens first.', 'I-drag ang kard sa ibang yugto: bubukas muna ang tunay na aksyon.')) ?></span></div>
  <div class="p-seg-mini bd-scope" role="group" aria-label="<?= e(t('Whose cases', 'Kaninong kaso')) ?>">
    <?php foreach (['mine' => t('Mine', 'Akin'), 'free' => t('Unclaimed', 'Walang may hawak'), 'all' => t('Everyone', 'Lahat')] as $sc => $lb): ?>
      <a href="?own=<?= e($sc) ?>" class="<?= $bscope === $sc ? 'p-on' : '' ?>" <?= $bscope === $sc ? 'aria-current="true"' : '' ?>><?= e($lb) ?> <b><?= (int) $bcount[$sc] ?></b></a>
    <?php endforeach; ?>
  </div>
</div>
<?php render_board($queue, $bmeta, $admin, $bscope, $queueErr); ?>
<script src="assets/js/board.js?v=<?= e(asset_version('../js/board.js')) ?>"></script>
<?php endif; ?>

<?php if ($tab === 'notes'): ?>
<!-- ---------- notifications ---------- -->
<?php $nHref = fn(string $v) => '?' . http_build_query(array_filter(['nview' => $v === 'all' ? 'all' : '', 'nq' => $nSearch, 'nsort' => $nSort !== 'newest' ? $nSort : ''])); ?>
<div class="p-band p-band--calm">
  <h2><?= e($nAll || $nSearch !== '' ? t('All notifications', 'Lahat ng abiso') : t('Unread', 'Hindi pa nababasa')) ?><span class="p-badge-n" id="notif-count"><?= (int) $notesTotal ?></span></h2>
  <div class="p-seg-mini bd-scope" role="group" aria-label="<?= e(t('Which notifications', 'Aling mga abiso')) ?>">
    <a href="<?= e($nHref('unread')) ?>" class="<?= !$nAll ? 'p-on' : '' ?>"><?= e(t('Unread', 'Hindi pa nababasa')) ?></a>
    <a href="<?= e($nHref('all')) ?>" class="<?= $nAll ? 'p-on' : '' ?>"><?= e(t('All', 'Lahat')) ?></a>
  </div>
  <form class="p-search" method="get" role="search">
    <?= p_icon('i-search', 16) ?>
    <input type="search" name="nq" placeholder="<?= e(t('Search notifications', 'Maghanap sa mga abiso')) ?>" value="<?= e($nSearch) ?>"
           aria-label="<?= e(t('Search notifications', 'Maghanap sa mga abiso')) ?>">
    <input type="hidden" name="nsort" value="<?= e($nSort) ?>"><?php if ($nAll): ?><input type="hidden" name="nview" value="all"><?php endif; ?>
    <?php foreach ($keep as $k => $v): ?><input type="hidden" name="<?= e($k) ?>" value="<?= e($v) ?>"><?php endforeach; ?>
  </form>
  <span class="p-spacer"></span>
  <?php if ($notesUnread > 0): ?>
  <form method="post"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="read_all">
    <button class="p-btn p-btn-ghost p-btn-sm" type="submit"><?= e(t('Mark all as read', 'Markahang nabasa ang lahat')) ?></button></form>
  <?php endif; ?>
  <form method="get">
    <input type="hidden" name="nq" value="<?= e($nSearch) ?>"><?php if ($nAll): ?><input type="hidden" name="nview" value="all"><?php endif; ?>
    <?php foreach ($keep as $k => $v): ?><input type="hidden" name="<?= e($k) ?>" value="<?= e($v) ?>"><?php endforeach; ?>
    <label class="p-pill-select"><span class="p-lbl"><?= e(t('Sort by', 'Ayusin ayon sa')) ?></span>
      <select name="nsort" data-autosubmit>
        <option value="newest" <?= $nSort === 'newest' ? 'selected' : '' ?>><?= e(t('Newest', 'Pinakabago')) ?></option>
        <option value="oldest" <?= $nSort === 'oldest' ? 'selected' : '' ?>><?= e(t('Oldest', 'Pinakaluma')) ?></option>
      </select></label>
  </form>
</div>

<!-- ---------- escalation requests (0073) ---------- -->
<?php if (!empty($escalations)): ?>
<div class="p-band p-band--calm">
  <h2><?= e(t('Escalation requests', 'Mga hiling na i-escalate')) ?><span class="p-badge-n"><?= count($escalations) ?></span></h2>
</div>
<div class="p-card p-notif-card" style="margin-bottom:28px"><div class="p-notif-list">
  <?php foreach ($escalations as $x): ?>
    <div class="p-notif p-unread">
      <span class="p-n-ico" style="background:var(--p-violet-bg);color:var(--p-violet-fg)"><?= p_icon('i-up', 18) ?></span>
      <div><div><span class="p-mono-id"><?= e($x['report']['tracking_id'] ?? '') ?></span> &middot; <?= e(category_label((string) ($x['report']['category'] ?? ''))) ?>
          &middot; <b><?= e(name_or($x['requester']['full_name'] ?? null, t('Tanod', 'Tanod'))) ?>:</b> <?= e($x['reason']) ?></div>
        <div class="p-when"><?= e(relative_time($x['created_at'])) ?><?php if (!empty($x['suggested_office'])): ?> &middot; <?= e(t('suggests ', 'mungkahi: ')) . e($x['suggested_office']) ?><?php endif; ?></div></div>
      <?php if (!empty($x['report']['id'])): ?>
        <a class="p-btn p-btn-sm p-btn-orange" href="case.php?id=<?= e($x['report']['id']) ?>"><?= e(t('Review', 'Suriin')) ?></a>
      <?php else: ?><span></span><?php endif; ?>
    </div>
  <?php endforeach; ?>
</div></div>
<?php endif; ?>

<div class="p-card p-notif-card" style="margin-bottom:28px"><div class="p-notif-list" id="notif-list">
  <?php if (!$notifications): ?>
    <div class="ss-caught" id="notif-empty"><?php if ($nSearch !== ''): ?>
        <b><?= e(t('Nothing matches that search.', 'Walang tugma sa hinanap.')) ?></b>
      <?php else: ?>
        <span class="ss-caught-ic" aria-hidden="true">&#10003;</span><b><?= e(t('All caught up', 'Wala nang hindi nababasa')) ?></b>
        <span><?= e(t('New notes appear here when a deadline is missed, a tanod files a resolution or someone needs you.', 'Lalabas dito ang bago kapag may lumampas sa oras, may nagsumite ng resolusyon o may nangangailangan sa iyo.')) ?></span>
        <?php if (!$nAll): ?><a href="<?= e($nHref('all')) ?>"><?= e(t('See the ones you have read', 'Tingnan ang mga nabasa na')) ?></a><?php endif; ?>
      <?php endif; ?></div>
  <?php endif; ?>
  <?php $lastDay = null; foreach ($notifications as $n): $dl = day_label($n['created_at']); if ($dl !== $lastDay): $lastDay = $dl; ?>
    <div class="ss-day"><?= e($dl) ?></div>
  <?php endif; ?>
    <?php $unread = empty($n['is_read']); ?>
    <div class="p-notif<?= $unread ? ' p-unread' : '' ?>">
      <span class="p-n-ico<?= str_starts_with((string) $n['message'], 'SMART') ? ' is-smart' : '' ?>"><?= str_starts_with((string) $n['message'], 'SMART') ? smart_brain(20) : p_icon('i-bell', 18) ?></span>
      <div class="p-n-body"><div class="p-n-line"><?= $unread ? '<span class="p-unread-dot"></span>' : '' ?><?= str_starts_with((string) $n['message'], 'SMART') ? '<span class="ss-smart-tag">SMART</span>' : '' ?><b><?= e($n['message']) ?></b></div><div class="p-when"><?= e(relative_time($n['created_at'])) ?></div></div>
      <div class="p-n-act">
      <?php if (!empty($n['report_id'])): ?>
        <a class="p-btn p-btn-sm p-btn-orange" data-nid="<?= $unread ? e($n['id']) : '' ?>" href="case.php?id=<?= e($n['report_id']) ?>"><?= e(t('Review', 'Suriin')) ?></a>
      <?php elseif (!empty($n['subject_user_id'])): ?>
        <?php // 0088 (Rose): a profile request opens that person's profile. ?>
        <a class="p-btn p-btn-sm p-btn-orange" data-nid="<?= $unread ? e($n['id']) : '' ?>" href="<?= ($n['subject']['role'] ?? '') === 'tanod' ? 'personnel.php' : 'residents.php' ?>?id=<?= e($n['subject_user_id']) ?>"><?= e(t('Review', 'Suriin')) ?></a>
      <?php endif; ?>
      </div>
      <form method="post" class="p-n-x"><?php if ($unread): ?><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="read_one"><input type="hidden" name="id" value="<?= e($n['id']) ?>"><input type="hidden" name="back" value="<?= (int) $npage ?>">
        <button class="p-n-check" type="submit" title="<?= e(t('Mark as read', 'Markahang nabasa')) ?>" aria-label="<?= e(t('Mark as read', 'Markahang nabasa')) ?>"><?= p_icon('i-check', 16) ?></button><?php endif; ?></form>
    </div>
  <?php endforeach; ?>
</div></div>

<div id="notes-pager"><?= pager($notesTotal, $npage, 'npage') ?></div>
<?php endif; ?>

<?php if ($tab === 'all'): ?>
<!-- ---------- complaint register ---------- -->
<?php $atc = count($attention ?? []); ?>
<div class="p-band">
  <h2><?= e(t('Reports', 'Mga Ulat')) ?><span class="p-badge-n p-badge-n--quiet" id="reports-count"><?= (int) $regTotal ?></span></h2>
  <a class="p-chip p-chip-band<?= $view === 'attention' ? ' p-on' : '' ?>" id="attention-chip"
     href="?<?= e(http_build_query(array_filter(['view' => $view === 'attention' ? '' : 'attention', 'q' => $search, 'status' => $filter, 'category' => $category, 'month' => $month]))) ?>">
    <?= e(t('Needs attention', 'Kailangang asikasuhin')) ?> <span class="p-chip-num<?= $atc > 0 ? ' p-hot' : '' ?>" id="attention-count"><?= $atc ?></span>
  </a>
  <form class="p-search" method="get" role="search">
    <?= p_icon('i-search', 16) ?>
    <input type="search" name="q" placeholder="<?= e(t('Search name, ID or category', 'Hanapin ang pangalan, ID o kategorya')) ?>" value="<?= e($search) ?>" aria-label="<?= e(t('Search reports', 'Maghanap sa mga ulat')) ?>">
    <input type="hidden" name="status" value="<?= e($filter) ?>">
    <input type="hidden" name="category" value="<?= e($category) ?>">
    <input type="hidden" name="month" value="<?= e($month) ?>">
    <input type="hidden" name="sort" value="<?= e($_GET['sort'] ?? 'newest') ?>">
    <input type="hidden" name="who" value="<?= e($who) ?>">
    <input type="hidden" name="tab" value="all">
    <input type="hidden" name="tanod" value="<?= e($tanod) ?>">
  </form>
  <span class="p-spacer"></span>
  <form method="get" class="ss-band-filters">
    <input type="hidden" name="tab" value="all">
    <input type="hidden" name="q" value="<?= e($search) ?>">
    <label class="p-pill-select"><?= p_icon('i-cal', 16) ?><span class="p-sr"><?= e(t('Filter by month', 'Salain ayon sa buwan')) ?></span>
      <input type="month" name="month" value="<?= e($month) ?>" data-autosubmit></label>
    <label class="p-pill-select"><span class="p-lbl"><?= e(t('Category', 'Kategorya')) ?></span>
      <select name="category" data-autosubmit>
        <option value=""><?= e(t('All', 'Lahat')) ?></option>
        <?php foreach (CATEGORIES as $c): ?>
          <option value="<?= e($c) ?>" <?= $category === $c ? 'selected' : '' ?>><?= e(category_label($c)) ?></option>
        <?php endforeach; ?>
      </select></label>
    <label class="p-pill-select"><span class="p-lbl"><?= e(t('Handled by', 'Hawak ni')) ?></span>
      <select name="who" data-autosubmit>
        <option value=""><?= e(t('Anyone', 'Kahit sino')) ?></option>
        <option value="unclaimed" <?= $who === 'unclaimed' ? 'selected' : '' ?>><?= e(t('Assigned to nobody', 'Walang hawak')) ?></option>
        <?php foreach ($adminList as $ad): ?>
          <option value="<?= e($ad['id']) ?>" <?= $who === $ad['id'] ? 'selected' : '' ?>><?= e($ad['id'] === $admin['id'] ? t('You', 'Ikaw') : display_name($ad['full_name'])) ?></option>
        <?php endforeach; ?>
      </select></label>
    <label class="p-pill-select"><span class="p-lbl"><?= e(t('Tanod', 'Tanod')) ?></span>
      <select name="tanod" data-autosubmit>
        <option value=""><?= e(t('Any', 'Anuman')) ?></option>
        <option value="needs" <?= $tanod === 'needs' ? 'selected' : '' ?>><?= e(t('Needs a tanod', 'Kailangan ng tanod')) ?></option>
        <option value="active" <?= $tanod === 'active' ? 'selected' : '' ?>><?= e(t('Tanod on it', 'May tanod na')) ?></option>
      </select></label>
    <label class="p-pill-select"><span class="p-lbl"><?= e(t('Status', 'Katayuan')) ?></span>
      <select name="status" data-autosubmit>
        <option value=""><?= e(t('All', 'Lahat')) ?></option>
        <?php foreach ([
            'under_review' => t('Under Review', 'Nirerepaso'),
            'in_progress'  => t('In Progress', 'Isinasagawa'),
            'resolved'     => t('Resolved/Completed', 'Nalutas/Nakumpleto'),
            'rejected'     => t('Rejected', 'Tinanggihan'),
            'overdue'      => t('Overdue', 'Lampas na sa takdang oras'),
            'escalated'    => t('Escalated', 'In-escalate'),
            'with_kagawad'  => t('With a Kagawad', 'Nasa Kagawad'),
            'with_chairman' => t('With the Chairman', 'Nasa Punong Barangay'),
        ] as $s => $lbl): ?>
          <option value="<?= e($s) ?>" <?= $filter === $s ? 'selected' : '' ?>><?= e($lbl) ?></option>
        <?php endforeach; ?>
      </select></label>
  </form>
</div>

<?php
// Saved views (Ace, 16 Oct): one tap sets the filters an admin reaches for most; counts are over all open cases.
$vOpen = fn(array $r) => !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true);
$vMine = count(array_filter($openRows ?? [], fn($r) => ($r['handler_id'] ?? null) === $admin['id']));
$vFree = count(array_filter($openRows ?? [], fn($r) => empty($r['handler_id'])));
$vLate = count(array_filter($openRows ?? [], fn($r) => $vOpen($r) && !empty($r['due_at']) && strtotime($r['due_at']) < time()));
$vBase = array_filter(['q' => $search]);
$vDefs = [
  ['attention', t('Needs attention', 'Kailangang asikasuhin'), $atc, array_merge($vBase, ['view' => 'attention']), $view === 'attention'],
  ['mine',      t('Assigned to me', 'Hawak ko'),               $vMine, array_merge($vBase, ['who' => $admin['id']]), $who === $admin['id'] && $view !== 'attention'],
  ['free',      t('Unassigned', 'Walang hawak'),               $vFree, array_merge($vBase, ['who' => 'unclaimed']), $who === 'unclaimed' && $view !== 'attention'],
  ['late',      t('Overdue', 'Lampas-oras'),                   $vLate, array_merge($vBase, ['status' => 'overdue']), $filter === 'overdue' && $view !== 'attention'],
];
$vAny = $view === 'attention' || $who !== '' || $filter !== '' || $category !== '' || $month !== '' || $tanod !== '' || $search !== '';
?>
<div class="ss-views" role="group" aria-label="<?= e(t('Saved views', 'Mga naka-save na tanaw')) ?>">
  <?php foreach ($vDefs as [$vk, $vl, $vn, $vq, $von]): ?>
    <a class="ss-view<?= $von ? ' on' : '' ?>" data-view="<?= e($vk) ?>" href="?<?= e(http_build_query($vq)) ?>"<?= $von ? ' aria-current="true"' : '' ?>><?= e($vl) ?> <b><?= (int) $vn ?></b></a>
  <?php endforeach; ?>
  <?php if ($vAny): ?><a class="ss-view ss-clear" href="cases.php?clear=1"><?= e(t('Clear filters', 'I-clear ang mga filter')) ?></a><?php endif; ?>
</div>

<div class="p-card p-table-card"><div class="p-tscroll">
  <table class="p-t ss-cases-t">
    <thead><tr>
      <th scope="col"><?= e(t('Resident', 'Residente')) ?></th>
      <th scope="col"><a class="p-th-sort" href="<?= e(sort_link('id', $sortCol, $sortDir)) ?>"><?= e(t('Complaint ID', 'ID ng Sumbong')) ?><?= sort_caret('id', $sortCol, $sortDir) ?></a></th>
      <th scope="col"><a class="p-th-sort" href="<?= e(sort_link('category', $sortCol, $sortDir)) ?>"><?= e(t('Category', 'Kategorya')) ?><?= sort_caret('category', $sortCol, $sortDir) ?></a></th>
      <th scope="col"><a class="p-th-sort" href="<?= e(sort_link('status', $sortCol, $sortDir)) ?>"><?= e(t('Status', 'Katayuan')) ?><?= sort_caret('status', $sortCol, $sortDir) ?></a></th>
      <th scope="col"><a class="p-th-sort" href="<?= e(sort_link('date', $sortCol, $sortDir)) ?>"><?= e(t('Filed', 'Naisampa')) ?><?= sort_caret('date', $sortCol, $sortDir) ?></a></th>
      <th scope="col"><?= e(t('SMART', 'SMART')) ?></th>
      <th scope="col"><?= e(t('Handler', 'Humahawak')) ?></th>
      <th scope="col"><?= e(t('Open now', 'Bukas ngayon')) ?></th>
      <th scope="col" class="p-right"><span class="p-sr"><?= e(t('Action', 'Aksyon')) ?></span></th>
    </tr></thead>
    <tbody id="reports-tbody">
      <?php if (!$reports): ?>
        <tr><td colspan="9" class="p-empty">
          <?= $search !== '' || $filter !== '' || $category !== '' || $month !== ''
              ? e(t('No complaint matches that search.', 'Walang sumbong na tugma sa hinanap.'))
              : e(t('No complaints have been filed yet.', 'Wala pang naisampang sumbong.')) ?>
        </td></tr>
      <?php endif; ?>
      <?php foreach ($reports as $r): ?>
        <tr class="p-click" data-href="case.php?id=<?= e($r['id']) ?>">
          <td>
            <?php if (!empty($r['is_anonymous'])): ?>
              <span class="p-anon"><?= e(t('Anonymous', 'Hindi nagpakilala')) ?></span>
            <?php else: ?>
              <div class="p-person"><span class="p-avatar p-av-sm" aria-hidden="true"><?= e(admin_initials($r['resident']['full_name'] ?? '')) ?></span><span><?= e(formal_or($r['resident']['full_name'] ?? null, t('Unknown', 'Hindi kilala'))) ?></span></div>
            <?php endif; ?>
          </td>
          <td><span class="p-mono-id"><?= e($r['tracking_id']) ?></span></td>
          <td><?= e(category_label($r['category'])) ?><?php if (!empty($r['location_label'])): ?><div class="p-sub"><?= e($r['location_label']) ?></div><?php endif; ?></td>
          <td><div class="p-badges">
            <span class="p-badge p-b-<?= e(status_class($r['status'])) ?>"><?= e(status_label($r['status'])) ?></span>
            <?php if (report_is_overdue($r)): ?><span class="p-badge p-b-denied"><?= e(t('Overdue', 'Lampas na sa takdang oras')) ?></span><?php endif; ?>
            <?php if (!empty($r['referred_to'])): ?><span class="p-badge p-b-violet"><?= e(t('Escalated to ', 'In-escalate sa ')) . e($r['referred_to']) ?></span><?php endif; ?>
            <?php if (!empty($r['higher_official'])): ?><span class="p-badge p-b-violet"><?= e(t('Escalated to ', 'In-escalate sa ')) . e($r['higher_official']) ?></span><?php endif; ?>
            <?php if (!empty($r['resolution_submitted_at'])): ?><span class="p-badge p-b-pending"><?= e(t('Awaiting approval', 'Naghihintay ng pag-apruba')) ?></span><?php endif; ?>
            <?php if (!empty($r['followed_up_at']) && !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true)): ?><span class="p-badge p-b-pending"><?= e(t('Followed up', 'Nag-follow up')) ?></span><?php endif; ?>
            <?php if (($r['reopened_count'] ?? 0) > 0): ?><span class="p-badge p-b-pending"><?= e(t('Reopened', 'Binuksang muli')) ?> <?= (int) $r['reopened_count'] ?>&times;</span><?php endif; ?>
            <?php if (!empty($r['appealed_at'])): ?><span class="p-badge p-b-pending" title="<?= e(t('Reinstated on appeal', 'Ibinalik dahil sa apela')) ?>"><?= e(t('Appealed', 'Inapela')) ?></span><?php endif; ?>
          </div></td>
          <td class="p-num"><?= e(short_date($r['created_at'])) ?></td>
          <td class="ss-smart"><?= smart_badge($r['triage'] ?? null) ?></td>
          <td><?= handler_cell($r, $admin['id']) ?></td>
          <td class="ss-open" data-report="<?= e($r['id']) ?>"></td>
          <td class="p-right"><a class="p-btn p-btn-ghost p-btn-sm" href="case.php?id=<?= e($r['id']) ?>"><?= e(t('Review', 'Suriin')) ?></a></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div></div>
<div id="reports-pager"><?= pager((int) $regTotal, $page) ?></div>

<?php endif; ?>

<script src="assets/vendor/supabase/supabase.js?v=2.117.3"></script>
<script>
// Realtime for the case list + notifications panel — explicit ask, 6 Sep
// 2026: "the entire system needs to work realtime." reports, dispatches,
// status_logs and notifications have all been in the supabase_realtime
// publication since migrations 0004/0046; the map (spatial.php) already
// proved the pattern out. This applies the same idiom here: a postgres_changes
// event is a signal to re-run the same authenticated PostgREST-equivalent
// query the initial page load used, never a payload to trust or patch in
// directly (0046's own stated reasoning — default replica identity, RLS
// still enforced through Realtime).
(function () {
  if (!window.supabase) { return; }
  const { createClient } = supabase;

  const TOKEN = <?= json_encode(access_token()) ?>;
  const ADMIN_ID = <?= json_encode($admin['id']) ?>;
  const CSRF = <?= json_encode(csrf_token()) ?>;
  // following a notification's action marks it read (a beacon, so the page change is not delayed)
  document.addEventListener('click', function (e) {
    const a = e.target.closest && e.target.closest('.p-notif a[data-nid]'); if (!a || !a.dataset.nid) return;
    const fd = new FormData(); fd.append('csrf', CSRF); fd.append('action', 'read_one'); fd.append('id', a.dataset.nid); fd.append('beacon', '1');
    try { navigator.sendBeacon('notifications.php', fd); } catch (x) { /* it can be marked by hand */ }
  });
  const sb = createClient(
    <?= json_encode(supabase_url()) ?>,
    <?= json_encode(supabase_key()) ?>,
    { accessToken: window.ssAccessToken(TOKEN) }
  );

  // The view this page loaded with. Realtime keeps re-querying against
  // this exact filter/sort/search, so a new complaint appears live only
  // where it would actually belong once the page is reloaded too — it
  // never silently changes what the admin is looking at.
  const SORT_COL   = <?= json_encode($SORTABLE[$sortCol]) ?>;
  const SORT_ASC   = <?= json_encode($sortDir === 'asc') ?>;
  const STATUS     = <?= json_encode($filter) ?>;
  // Mirrors the STATUS_GROUPS constant in this same file exactly, so a
  // live refresh applies the same grouped filter a reload would.
  const STATUS_GROUPS = <?= json_encode(STATUS_GROUPS) ?>;
  const OPEN_STATES = <?= json_encode(OPEN_STATES) ?>;
  const CATEGORY   = <?= json_encode($category) ?>;
  const MONTH_FROM = <?= json_encode($month !== '' ? (DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', new DateTimeZone('Asia/Manila')))->format(DateTimeInterface::ATOM) : null) ?>;
  const MONTH_TO   = <?= json_encode($month !== '' ? (DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', new DateTimeZone('Asia/Manila')))->modify('first day of next month')->format(DateTimeInterface::ATOM) : null) ?>;
  const SEARCH     = <?= json_encode($search) ?>;
  const N_SEARCH   = <?= json_encode($nSearch) ?>;
  const N_ALL      = <?= json_encode($nAll) ?>;
  const N_OLDEST   = <?= json_encode($nSort === 'oldest') ?>;
  const VIEW       = <?= json_encode($view) ?>;
  const WHO        = <?= json_encode($who) ?>;
  const TAB        = <?= json_encode($tab) ?>;
  const PAGE       = <?= (int) $page ?>;
  const NPAGE      = <?= (int) $npage ?>;
  const PER        = <?= (int) PER_PAGE ?>;
  const TANOD      = <?= json_encode($tanod) ?>;
  const STAGE      = <?= json_encode($stage) ?>;
  const LEVEL_LABEL = { urgent: T('Urgent', 'Apurahan'), high: T('High', 'Mataas'), normal: T('Normal', 'Karaniwan'), low: T('Low', 'Mababa') };
  const LEVEL_CLASS = { urgent: 'denied', high: 'pending', normal: 'progress', low: 'grey' };
  // Same markup as smart_badge() above: the level's word always beside its colour.
  function smartBadge(tr) {
    if (!tr || !tr.effective_level) return '<span class="p-sub">' + T('Not scored', 'Walang marka') + '</span>';
    let o = '<span class="p-badge p-b-' + (LEVEL_CLASS[tr.effective_level] || 'grey') + '">' + escapeHtml(LEVEL_LABEL[tr.effective_level] || tr.effective_level) + '</span><small class="ss-score"> ' + (tr.score | 0) + '</small>';
    if (tr.override_level) o += '<small class="ss-set" title="' + T('Set by an admin', 'Itinakda ng admin') + '">' + T('set by admin', 'itinakda ng admin') + '</small>';
    if ((tr.possible_duplicates | 0) > 0) o += '<span class="p-badge p-b-violet ss-dup">' + T('Possible duplicate', 'Maaaring doble') + '</span>';
    return o;
  }
  // The pager, as pager() draws it, for the pages the live refresh redraws.
  function pagerHtml(total, page, param) {
    const pages = Math.max(1, Math.ceil(total / PER));
    if (pages <= 1) return '';
    const href = n => { const u = new URLSearchParams(location.search); u.set(param, n); return '?' + u.toString(); };
    const from = Math.max(1, Math.min(page - 2, pages - 4)), to = Math.min(pages, from + 4);
    let o = '<nav class="ss-pager" aria-label="' + T('Pages', 'Mga pahina') + '">';
    o += page > 1 ? '<a href="' + href(page - 1) + '" rel="prev">&lsaquo; ' + T('Previous', 'Nakaraan') + '</a>' : '<span class="off">&lsaquo; ' + T('Previous', 'Nakaraan') + '</span>';
    if (from > 1) o += '<a href="' + href(1) + '">1</a>' + (from > 2 ? '<span class="gap">&hellip;</span>' : '');
    for (let i = from; i <= to; i++) o += i === page ? '<span class="on" aria-current="page">' + i + '</span>' : '<a href="' + href(i) + '">' + i + '</a>';
    if (to < pages) o += (to < pages - 1 ? '<span class="gap">&hellip;</span>' : '') + '<a href="' + href(pages) + '">' + pages + '</a>';
    o += page < pages ? '<a href="' + href(page + 1) + '" rel="next">' + T('Next', 'Susunod') + ' &rsaquo;</a>' : '<span class="off">' + T('Next', 'Susunod') + ' &rsaquo;</span>';
    return o + '<span class="of">' + ((page - 1) * PER + 1) + '&ndash;' + Math.min(total, page * PER) + ' ' + T('of', 'sa') + ' ' + total + '</span></nav>';
  }
  function handlerCell(r) {
    if (!r.handler_id) return '<span class="p-sub">' + T('Nobody yet', 'Wala pa') + '</span>';
    const nm = r.handler_id === ADMIN_ID ? T('You', 'Ikaw') : window.ssName((r.handler && r.handler.full_name) || '');
    return '<span class="ss-who">' + window.ssAvatar(r.handler_id, (r.handler && r.handler.full_name) || '', 24) + escapeHtml(nm) + '</span>' + rankChip(r.handler && r.handler.official_role);
  }
  // Which rung the handler sits on, always with its word (the colours of the ladder, 14 Oct).
  function rankChip(role) {
    const rank = role === 'kagawad' ? 'kagawad' : role === 'chairman' ? 'chair' : 'staff';
    const label = rank === 'kagawad' ? T('Councilor', 'Kagawad') : rank === 'chair' ? T('Chairman', 'Punong Barangay') : role === 'secretary' ? T('Secretary', 'Kalihim') : T('Staff', 'Kawani');
    return '<span class="rank' + (rank === 'chair' ? ' chair' : '') + '" data-r="' + rank + '"><i></i>' + escapeHtml(label) + '</span>';
  }
  const STATUS_LABEL = <?= json_encode(status_labels(), JSON_UNESCAPED_UNICODE) ?>;

  function escapeHtml(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }
  const CATEGORY_LABEL = <?= json_encode(array_combine(CATEGORIES, array_map('category_label', CATEGORIES)), JSON_UNESCAPED_UNICODE) ?>;
  const titleCase = s => String(s ?? '').replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
  function statusClass(s) {
    // Mirrors status_class() in layout.php: the preview's badge colours.
    switch (s) {
      case 'pending_review': return 'pending';
      case 'validated': case 'assigned':
      case 'in_progress': case 'offline_investigation': return 'progress';
      case 'resolved': return 'done';
      case 'closed': case 'archived': return 'grey';
      case 'rejected': return 'denied';
      default: return 'pending';
    }
  }
  function shortDate(iso) {
    if (!iso) return '';
    const parts = new Intl.DateTimeFormat('en-US',
      { timeZone: 'Asia/Manila', month: '2-digit', day: '2-digit', year: '2-digit' })
      .formatToParts(new Date(iso));
    const get = t => (parts.find(p => p.type === t) || {}).value || '';
    return get('month') + '/' + get('day') + '/' + get('year');
  }
  function relativeTime(iso) {
    if (!iso) return '';
    const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
    if (mins < 1) return T('Just now', 'Ngayon lang');
    if (mins < 60) return mins + T(' min ago', ' minutong nakalipas');
    if (mins < 1440) return Math.floor(mins / 60) + T(' hr ago', ' oras na nakalipas');
    return new Intl.DateTimeFormat('en-US',
      { timeZone: 'Asia/Manila', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
      .format(new Date(iso));
  }
  function isAttention(r) {
    const open = !['resolved', 'closed', 'archived', 'rejected', 'cancelled'].includes(r.status);
    const overdue = open && r.due_at && new Date(r.due_at).getTime() < Date.now();
    return overdue || (open && !!r.followed_up_at) || !!r.resolution_submitted_at
        || !!r.awaiting_unit_since || r.status === 'pending_review';
  }

  function renderReports(all, total, attentionN) {
    const filtered = all;
    document.getElementById('reports-count').textContent = total;
    if (attentionN != null) document.getElementById('attention-count').textContent = attentionN;
    document.getElementById('reports-pager').innerHTML = pagerHtml(total, PAGE, 'page');

    const tbody = document.getElementById('reports-tbody');
    if (!filtered.length) {
      tbody.innerHTML = '<tr><td colspan="9" class="p-empty">' +
        (SEARCH || STATUS || CATEGORY || MONTH_FROM ? T('No complaint matches that search.', 'Walang sumbong na tugma sa hinanap.')
                                                    : T('No complaints have been filed yet.', 'Wala pang naisampang sumbong.')) +
        '</td></tr>';
      return;
    }
    tbody.innerHTML = filtered.map(r => {
      const nm = String((r.resident && r.resident.full_name) || '').trim() || T('Unknown', 'Hindi kilala');
      const ini = String(nm).trim().split(/\s+/).filter(Boolean);
      const who = r.is_anonymous
        ? '<span class="p-anon">' + T('Anonymous', 'Hindi nagpakilala') + '</span>'
        : '<div class="p-person"><span class="p-avatar p-av-sm" aria-hidden="true">' + escapeHtml(((ini[0] || '?')[0] + (ini.length > 1 ? ini[ini.length - 1][0] : '')).toUpperCase()) + '</span><span>' + escapeHtml(nm) + '</span></div>';
      // 0072: Overdue (the admin's date has passed) replaces Escalated;
      // escalation is now a referral, shown by name.
      const open = !['resolved', 'closed', 'archived', 'rejected', 'cancelled'].includes(r.status);
      const escalated =
        (open && r.due_at && new Date(r.due_at) < new Date()
          ? '<span class="p-badge p-b-denied">' + T('Overdue', 'Lampas na sa takdang oras') + '</span>' : '') +
        (r.referred_to
          ? '<span class="p-badge p-b-violet">' + T('Escalated to ', 'In-escalate sa ') + escapeHtml(r.referred_to) + '</span>' : '') +
        (r.higher_official
          ? '<span class="p-badge p-b-violet">' + T('Escalated to ', 'In-escalate sa ') + escapeHtml(r.higher_official) + '</span>' : '') +
        (r.resolution_submitted_at
          ? '<span class="p-badge p-b-pending">' + T('Awaiting approval', 'Naghihintay ng pag-apruba') + '</span>' : '') +
        (open && r.followed_up_at
          ? '<span class="p-badge p-b-pending">' + T('Followed up', 'Nag-follow up') + '</span>' : '');
      const reopened = (r.reopened_count || 0) > 0
        ? '<span class="p-badge p-b-pending">' + T('Reopened ', 'Binuksang muli ') + r.reopened_count + '&times;</span>' : '';
      const appealed = r.appealed_at
        ? '<span class="p-badge p-b-pending" title="' + T('Reinstated on appeal', 'Ibinalik dahil sa apela') + '">' + T('Appealed', 'Inapela') + '</span>' : '';
      return '<tr class="p-click" data-href="case.php?id=' + encodeURIComponent(r.id) + '">' +
        '<td>' + who + '</td>' +
        '<td><span class="p-mono-id">' + escapeHtml(r.tracking_id) + '</span></td>' +
        '<td>' + escapeHtml(CATEGORY_LABEL[r.category] || titleCase(r.category)) +
          (r.location_label ? '<div class="p-sub">' + escapeHtml(r.location_label) + '</div>' : '') + '</td>' +
        '<td><div class="p-badges"><span class="p-badge p-b-' + statusClass(r.status) + '">' +
          escapeHtml(STATUS_LABEL[r.status] || titleCase(r.status)) + '</span>' + escalated + reopened + appealed + '</div></td>' +
        '<td class="p-num">' + shortDate(r.created_at) + '</td>' +
        '<td class="ss-smart">' + smartBadge(r.triage) + '</td>' +
        '<td>' + handlerCell(r) + '</td>' +
        '<td class="ss-open" data-report="' + escapeHtml(r.id) + '"></td>' +
        '<td class="p-right"><a class="p-btn p-btn-ghost p-btn-sm" href="case.php?id=' +
          encodeURIComponent(r.id) + '">' + T('Review', 'Suriin') + '</a></td>' +
        '</tr>';
    }).join('');
  }

  const BRAIN_SVG = <?= json_encode(smart_brain(20)) ?>;
  // Today / Yesterday / "Oct 12", in Manila, to group the list like a timeline.
  function dayLabel(iso) {
    const fmt = d => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila' }).format(d);
    const d = fmt(new Date(iso)), t = fmt(new Date()), y = fmt(new Date(Date.now() - 86400000));
    return d === t ? T('Today', 'Ngayon') : d === y ? T('Yesterday', 'Kahapon')
      : new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Manila', month: 'short', day: 'numeric' }).format(new Date(iso));
  }
  function renderNotifications(rows) {
    document.getElementById('notif-count').textContent = rows.length;
    const list = document.getElementById('notif-list');
    if (!rows.length) {
      list.innerHTML = '<p class="p-empty" id="notif-empty">' + (N_SEARCH
        ? T('No notification matches that search.', 'Walang abisong tugma sa hinanap.')
        : T('Nothing new. Notifications appear here when a report is escalated, a deadline is missed, or a tanod files a resolution.',
            'Walang bago. Lalabas dito ang abiso kapag may ulat na na-escalate, may lumampas sa takdang oras, o may tanod na nagsumite ng resolusyon.')) + '</p>';
      return;
    }
    let lastDay = null;
    list.innerHTML = rows.map(n => {
      const dl = dayLabel(n.created_at);
      const head = dl !== lastDay ? '<div class="ss-day">' + escapeHtml(dl) + '</div>' : '';
      lastDay = dl;
      const unread = !n.is_read, nid = unread ? ' data-nid="' + escapeHtml(n.id) + '"' : '';
      const review = n.report_id
        ? '<a class="p-btn p-btn-sm p-btn-orange"' + nid + ' href="case.php?id=' + encodeURIComponent(n.report_id) + '">' + T('Review', 'Suriin') + '</a>'
        : n.subject_user_id
          ? '<a class="p-btn p-btn-sm p-btn-orange"' + nid + ' href="' + ((n.subject && n.subject.role) === 'tanod' ? 'personnel.php' : 'residents.php') + '?id=' + encodeURIComponent(n.subject_user_id) + '">' + T('Review', 'Suriin') + '</a>'
          : '';
      const check = unread ? '<form method="post" class="p-n-x"><input type="hidden" name="csrf" value="' + escapeHtml(CSRF) + '"><input type="hidden" name="action" value="read_one"><input type="hidden" name="id" value="' + escapeHtml(n.id) + '"><input type="hidden" name="back" value="' + NPAGE + '"><button class="p-n-check" type="submit" title="' + T('Mark as read', 'Markahang nabasa') + '"><svg width="16" height="16" aria-hidden="true"><use href="#i-check"/></svg></button></form>' : '<form class="p-n-x"></form>';
      return head + '<div class="p-notif' + (unread ? ' p-unread' : '') + '">' +
        '<span class="p-n-ico' + (String(n.message).indexOf('SMART') === 0 ? ' is-smart">' + BRAIN_SVG : '"><svg width="18" height="18" aria-hidden="true"><use href="#i-bell"/></svg>') + '</span>' +
        '<div class="p-n-body"><div class="p-n-line">' + (unread ? '<span class="p-unread-dot"></span>' : '') + (String(n.message).indexOf('SMART') === 0 ? '<span class="ss-smart-tag">SMART</span>' : '') + '<b>' + escapeHtml(n.message) + '</b></div>' +
        '<div class="p-when">' + escapeHtml(relativeTime(n.created_at)) + '</div></div>' +
        '<div class="p-n-act">' + review + '</div>' + check + '</div>';
    }).join('');
  }

  const STAGE_ACTION = {};
  function waitingText(iso) {
    if (!iso) return '';
    const h = Math.floor((Date.now() - new Date(iso).getTime()) / 3600000);
    return h < 1 ? T('under 1 h', 'wala pang 1 oras') : h < 48 ? h + ' ' + T('h', 'oras') : Math.floor(h / 24) + ' ' + T('days', 'araw');
  }
  async function refreshBoard() {
    if (window.ssBoardBusy && window.ssBoardBusy()) return;   // not while a card is in someone's hand
    try {
      const r = await fetch(location.href, { credentials: 'same-origin', cache: 'no-store' });
      if (!r.ok) return;
      const doc = new DOMParser().parseFromString(await r.text(), 'text/html');
      const nb = doc.getElementById('board'), cur = document.getElementById('board');
      if (nb && cur) cur.innerHTML = nb.innerHTML;
      const sc = doc.querySelector('.bd-scope'), cs = document.querySelector('.bd-scope');
      if (sc && cs) cs.innerHTML = sc.innerHTML;
    } catch (e) { /* keep what is on screen */ }
  }
  window.ssBoardRefresh = refreshBoard;
  async function loadQueue() {
    const { data, error } = await sb.rpc('smart_queue', { p_stage: null, p_limit: 500 });
    if (error || !Array.isArray(data)) return;   // keep what is on screen
    const rows = STAGE ? data.filter(q => q.stage === STAGE) : data;
    document.getElementById('queue-count').textContent = rows.length;
    const page = rows.slice((PAGE - 1) * PER, PAGE * PER);
    const tb = document.getElementById('queue-tbody');
    tb.innerHTML = !page.length ? '<tr><td colspan="5" class="p-empty">' + T('Nothing waiting on you. Every open case has someone on it.', 'Walang naghihintay sa iyo. May nakatalaga sa bawat bukás na kaso.') + '</td></tr>'
      : page.map(q => {
          const why = (q.reasons || []).map(r => (r.detail || r.factor) + ' +' + (r.points | 0));
          return '<tr class="p-click" data-href="case.php?id=' + encodeURIComponent(q.report_id) + '"><td><span class="p-mono-id">' + escapeHtml(q.tracking_id) + '</span><div class="p-sub">' + escapeHtml(q.subject) + ' &middot; ' + escapeHtml(CATEGORY_LABEL[q.category] || titleCase(q.category)) + '</div></td>' +
            '<td>' + smartBadge({ effective_level: q.level === 'unscored' ? null : q.level, score: 0 }) + '</td>' +
            '<td><a class="p-btn p-btn-sm p-btn-orange" href="case.php?id=' + encodeURIComponent(q.report_id) + '">' + escapeHtml(q.next_action) + '</a></td>' +
            '<td class="p-num">' + escapeHtml(waitingText(q.waiting_since)) + '</td>' +
            '<td><div class="ss-bar" title="' + escapeHtml(why.join(' · ')) + '"><i style="width:' + Math.min(100, q.priority | 0) + '%"></i></div><small class="ss-why">' + escapeHtml(why.slice(0, 3).join(' · ')) + '</small></td></tr>';
        }).join('');
    document.getElementById('queue-pager').innerHTML = pagerHtml(rows.length, PAGE, 'page');
  }

  async function loadReports() {
    let q = sb.from('reports')
      .select('id,tracking_id,subject,category,status,created_at,is_anonymous,location_label,'
        + 'due_at,awaiting_unit_since,reopened_count,appealed_at,referred_to,higher_official,followed_up_at,resolution_submitted_at,'
        + 'resident:users!reports_resident_id_fkey(full_name),handler_id,handler:users!reports_handler_id_fkey(full_name,official_role),'
        + 'triage:report_triage(score,effective_level,override_level,possible_duplicates)', { count: 'exact' })
      .is('deleted_at', null)
      .order(SORT_COL, { ascending: SORT_ASC });
    q = VIEW === 'attention' ? q.limit(500) : q.range((PAGE - 1) * PER, PAGE * PER - 1);
    if (TANOD === 'needs') q = q.in('status', ['validated']);
    else if (TANOD === 'active') q = q.in('status', ['assigned', 'in_progress', 'offline_investigation']);
    if (STATUS === 'overdue') q = q.in('status', OPEN_STATES).lt('due_at', new Date().toISOString());
    else if (STATUS === 'escalated' && !SEARCH) q = q.or('referred_to.not.is.null,higher_official.not.is.null');
    else if (STATUS === 'with_kagawad') q = q.eq('tier', 1);
    else if (STATUS === 'with_chairman') q = q.eq('tier', 2);
    else if (STATUS && STATUS !== 'escalated') q = q.in('status', STATUS_GROUPS[STATUS] || [STATUS]);
    if (CATEGORY) q = q.eq('category', CATEGORY);
    if (WHO === 'unclaimed') q = q.is('handler_id', null);
    else if (WHO) q = q.eq('handler_id', WHO);
    if (MONTH_FROM) q = q.gte('created_at', MONTH_FROM).lt('created_at', MONTH_TO);
    if (SEARCH) {
      const needle = SEARCH.replace(/[,()"\\*]/g, ' ');   // mirrors the PHP above
      q = q.or('tracking_id.ilike.*' + needle + '*,subject.ilike.*' + needle + '*');
    }
    const { data, error, count } = await q;
    if (error) return; // stale view is safer than a half-rendered one
    // Escalated with a search: the search already uses the one "or", so
    // the escalated rows are picked here instead.
    let rows = (STATUS === 'escalated' && SEARCH) ? (data || []).filter(r => r.referred_to || r.higher_official) : (data || []);
    let total = count == null ? rows.length : count;
    if (VIEW === 'attention') { const att = rows.filter(isAttention); total = att.length; rows = att.slice((PAGE - 1) * PER, PAGE * PER); }
    // the chip counts what needs attention across every open case, not this page
    const od = await sb.from('reports').select('status,due_at,followed_up_at,resolution_submitted_at,awaiting_unit_since')
      .is('deleted_at', null).in('status', OPEN_STATES).limit(500);
    renderReports(rows, total, od.error ? null : (od.data || []).filter(isAttention).length);
    if (window.ssPaintOpen) window.ssPaintOpen();
  }

  async function loadNotifications() {
    let nq = sb.from('notifications')
      .select('id,kind,message,created_at,is_read,report_id,subject_user_id,subject:users!notifications_subject_user_id_fkey(role)', { count: 'exact' })
      .eq('user_id', ADMIN_ID)
      .order('created_at', { ascending: N_OLDEST })
      .range((NPAGE - 1) * PER, NPAGE * PER - 1);
    // Same rule as the PHP above: a search includes read notifications.
    // the same rules as the PHP above: the engine's watcher notes are the cards above the list; unread unless searching or "All"
    nq = nq.not('message', 'like', 'SMART: recurring*').not('message', 'like', 'SMART: spike*').not('message', 'like', 'SMART:*has had no update for*');
    nq = N_SEARCH ? nq.ilike('message', '*' + N_SEARCH.replace(/[,()"\\*]/g, ' ') + '*')
                  : (N_ALL ? nq : nq.eq('is_read', false));
    const { data, error, count } = await nq;
    if (error) return;
    renderNotifications(data || []);
    const np = document.getElementById('notes-pager');
    if (np) np.innerHTML = pagerHtml(count == null ? (data || []).length : count, NPAGE, 'npage');
  }

  // Bursts (a batch import, several tanods updating at once) collapse into
  // one refetch instead of one per row.
  const debounced = (fn, timerRef) => () => {
    clearTimeout(timerRef.id);
    timerRef.id = setTimeout(fn, 250);
  };
  // only the part of the page that is on screen is refreshed
  const kickReports = debounced(TAB === 'all' ? loadReports : TAB === 'next' ? refreshBoard : () => {}, { id: null });
  const kickNotifs  = debounced(TAB === 'notes' ? loadNotifications : () => {}, { id: null });

  let wasDown = false;
  sb.channel('cases-list')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' }, kickReports)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications',
                               filter: 'user_id=eq.' + ADMIN_ID }, kickNotifs)
    .subscribe(status => {
      const badge = document.getElementById('live-badge'),
            text  = document.getElementById('live-badge-text');
      if (status === 'SUBSCRIBED') {
        badge.classList.remove('p-down'); text.textContent = T('Live', 'Live');
        // Nothing is replayed for the time the socket was down.
        if (wasDown) { wasDown = false; kickReports(); kickNotifs(); }
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        wasDown = true;
        badge.classList.add('p-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
      }
    });
})();
</script>

<?php layout_foot(); ?>
