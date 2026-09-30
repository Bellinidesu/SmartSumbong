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

$admin = require_admin();
$db    = db();

session_start_once();

// Coming back from a case should land on the list you left, not on an
// unfiltered one you have to rebuild. Any explicit parameter wins; a bare
// visit restores what you last looked at.
if (!isset($_GET['q'], $_GET['status'], $_GET['sort'], $_GET['month'], $_GET['category'])
    && ($_SERVER['QUERY_STRING'] ?? '') === '' && !empty($_SESSION['cases_view'])) {
    $_GET = $_SESSION['cases_view'] + $_GET;
}

// The seven categories are fixed per the Scope and Limitations — the same
// list cases.php's category dropdown and the resident app's own filing
// form both draw from.
const CATEGORIES = [
    'street_obstruction', 'public_safety_infrastructure', 'environmental_waste_hazard',
    'animal_welfare', 'traffic_violation', 'barangay_service', 'peace_order_nuisance',
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
// The Notification panel's own search and order (Rose, 27 Sep 2026: both
// were only drawn, never read).
$nSearch  = trim((string) ($_GET['nq'] ?? ''));
$nSort    = ($_GET['nsort'] ?? 'newest') === 'oldest' ? 'oldest' : 'newest';

if (!in_array($category, CATEGORIES, true)) { $category = ''; }
if (!preg_match('/^\d{4}-\d{2}$/', $month)) { $month = ''; }
if (!isset(STATUS_GROUPS[$filter])) { $filter = ''; }

// Clicking a column heading sorts by it; clicking the same one again
// reverses. PostgREST cannot order by an embedded resident name, so that
// column is not offered as a sort.
$SORTABLE = ['id' => 'tracking_id', 'category' => 'category', 'status' => 'status', 'date' => 'created_at'];
$sortCol  = $_GET['by'] ?? 'date';
$sortDir  = ($_GET['dir'] ?? 'desc') === 'asc' ? 'asc' : 'desc';
if (!isset($SORTABLE[$sortCol])) { $sortCol = 'date'; }
$sort = $SORTABLE[$sortCol] . '.' . $sortDir;

$_SESSION['cases_view'] = array_filter([
    'q' => $search, 'status' => $filter, 'category' => $category, 'month' => $month, 'view' => $view,
    'by' => $sortCol, 'dir' => $sortDir,
], fn($v) => $v !== '');

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

try {
    // The embedded resident is a PostgREST foreign-key expansion; the
    // join happens in the database, not in a second round trip.
    $query = [
        'select' => 'id,tracking_id,subject,category,status,created_at,is_anonymous,location_label,'
                  . 'due_at,awaiting_unit_since,reopened_count,appealed_at,referred_to,followed_up_at,resolution_submitted_at,'
                  . 'resident:users!reports_resident_id_fkey(full_name)',
        'deleted_at' => 'is.null',
        'order'      => $sort,
        'limit'      => '100',
    ];
    if ($filter !== '') {
        $query['status'] = 'in.(' . implode(',', STATUS_GROUPS[$filter]) . ')';
    }
    if ($category !== '') {
        $query['category'] = 'eq.' . $category;
    }
    if ($month !== '') {
        $mtz   = new DateTimeZone('Asia/Manila');
        $start = DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', $mtz);
        $end   = $start->modify('first day of next month');
        $query['and'] = "(created_at.gte.{$start->format(DateTimeInterface::ATOM)},"
                       . "created_at.lt.{$end->format(DateTimeInterface::ATOM)})";
    }
    if ($search !== '') {
        // Match either the tracking id or the subject line. Commas,
        // parentheses, quotes, backslashes and * are PostgREST's own
        // or=() syntax; left in, a search like "poste (ilaw)" failed to
        // parse and the whole list came back as a reference-code error.
        $needle = preg_replace('/[,()"\\\\*]/', ' ', $search);
        $query['or'] = "(tracking_id.ilike.*{$needle}*,subject.ilike.*{$needle}*)";
    }
    $reports = $db->select('reports', $query);

    // "Needs attention" is the question an admin actually opens this page
    // with: what is late, what nobody has picked up, and what is still
    // sitting unreviewed. Three separate conditions, one chip.
    $attention = array_values(array_filter($reports, function (array $r) {
        $open    = !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true);
        $overdue = $open && !empty($r['due_at']) && strtotime($r['due_at']) < time();
        return $overdue
            || ($open && !empty($r['followed_up_at']))   // 0072: the resident asked again
            || !empty($r['resolution_submitted_at'])      // 0073: waiting for approval
            || !empty($r['awaiting_unit_since'])
            || $r['status'] === 'pending_review';
    }));
    if ($view === 'attention') { $reports = $attention; }

    // Unread by default; a search looks through read ones too, since
    // what an admin searches for is usually something already seen.
    $nq = [
        'select'  => 'id,kind,message,created_at,is_read,report_id',
        'user_id' => 'eq.' . $admin['id'],
        'order'   => 'created_at.' . ($nSort === 'oldest' ? 'asc' : 'desc'),
        'limit'   => $nSearch !== '' ? '50' : '20',
    ];
    if ($nSearch !== '') {
        $nq['message'] = 'ilike.*' . preg_replace('/[,()"\\\\*]/', ' ', $nSearch) . '*';
    } else {
        $nq['is_read'] = 'is.false';
    }
    $notifications = $db->select('notifications', $nq);

    // 0073 — Manage Escalation Request: tanods' requests waiting on an admin.
    try {
        $escalations = $db->select('escalation_requests', [
            'select' => 'id,reason,suggested_office,created_at,'
                      . 'report:reports!escalation_requests_report_id_fkey(id,tracking_id,category),'
                      . 'requester:users!escalation_requests_requested_by_fkey(full_name)',
            'status' => 'eq.pending',
            'order'  => 'created_at.asc',
        ]);
    } catch (SupabaseError) {
        $escalations = [];
    }
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

layout_head(t('Case Reports', 'Mga Sumbong'), 'cases.php');
?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<!-- ---------- notifications ---------- -->
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title"><?= e(t('Notification', 'Abiso')) ?> (<span id="notif-count"><?= count($notifications) ?></span>)
      <span class="live-badge" id="live-badge" title="<?= e(t('Updates as they happen — no reload needed', 'Nag-a-update habang nangyayari — hindi na kailangang i-reload')) ?>">
        <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text"><?= e(t('Live', 'Live')) ?></span>
      </span>
    </h2>
    <?php
    // Both forms carry the Reports panel's filters along, so searching
    // notifications does not reset the list below.
    $keep = array_filter(['q' => $search, 'status' => $filter, 'category' => $category,
                          'month' => $month, 'view' => $view, 'by' => $sortCol, 'dir' => $sortDir],
                         fn($v) => $v !== '');
    ?>
    <form class="panel-search" method="get">
      <?= nav_icon('search') ?>
      <input type="search" name="nq" placeholder="<?= e(t('Search Here', 'Maghanap Dito')) ?>" value="<?= e($nSearch) ?>"
             aria-label="<?= e(t('Search notifications', 'Maghanap sa mga abiso')) ?>">
      <input type="hidden" name="nsort" value="<?= e($nSort) ?>">
      <?php foreach ($keep as $k => $v): ?><input type="hidden" name="<?= e($k) ?>" value="<?= e($v) ?>"><?php endforeach; ?>
    </form>
    <form class="panel-sort" method="get">
      <input type="hidden" name="nq" value="<?= e($nSearch) ?>">
      <?php foreach ($keep as $k => $v): ?><input type="hidden" name="<?= e($k) ?>" value="<?= e($v) ?>"><?php endforeach; ?>
      <label class="filter-option">
        <?= e(t('Sort by:', 'Ayusin ayon sa:')) ?>
        <select name="nsort" onchange="this.form.submit()">
          <option value="newest" <?= $nSort === 'newest' ? 'selected' : '' ?>><?= e(t('Newest first', 'Pinakabago muna')) ?></option>
          <option value="oldest" <?= $nSort === 'oldest' ? 'selected' : '' ?>><?= e(t('Oldest first', 'Pinakaluma muna')) ?></option>
        </select>
      </label>
    </form>
  </header>

  <div class="notif-list" id="notif-list">
    <?php if (!$notifications): ?>
      <p class="empty" id="notif-empty"><?= $nSearch !== ''
          ? e(t('No notification matches that search.', 'Walang abisong tugma sa hinanap.'))
          : e(t('Nothing new. Notifications appear here when a report is escalated, a deadline is missed, or a tanod files a resolution.',
                'Walang bago. Lalabas dito ang abiso kapag may ulat na na-escalate, may lumampas sa takdang oras, o may tanod na nagsumite ng resolusyon.')) ?></p>
    <?php endif; ?>

    <?php foreach ($notifications as $n): ?>
      <article class="notif">
        <span class="notif-dot" aria-hidden="true"></span>
        <div class="notif-body">
          <p class="notif-msg"><?= e($n['message']) ?></p>
          <p class="notif-when"><?= e(relative_time($n['created_at'])) ?></p>
        </div>
        <?php if (!empty($n['report_id'])): ?>
          <a class="btn-review" href="case.php?id=<?= e($n['report_id']) ?>"><?= e(t('Review', 'Suriin')) ?></a>
        <?php endif; ?>
      </article>
    <?php endforeach; ?>
  </div>
</section>

<!-- ---------- escalation requests (0073) ---------- -->
<?php if (!empty($escalations)): ?>
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title"><?= e(t('Escalation Requests', 'Mga Hiling na I-escalate')) ?> (<?= count($escalations) ?>)</h2>
  </header>
  <div class="notif-list">
    <?php foreach ($escalations as $x): ?>
      <article class="notif">
        <span class="notif-dot" aria-hidden="true"></span>
        <div class="notif-body">
          <p class="notif-msg">
            <strong class="mono"><?= e($x['report']['tracking_id'] ?? '') ?></strong>
            &middot; <?= e(category_label((string) ($x['report']['category'] ?? ''))) ?>
            &middot; <?= e($x['requester']['full_name'] ?? t('Tanod', 'Tanod')) ?>:
            <?= e($x['reason']) ?>
          </p>
          <p class="notif-when"><?= e(relative_time($x['created_at'])) ?><?php if (!empty($x['suggested_office'])): ?> &middot; <?= e(t('suggests ', 'mungkahi: ')) . e($x['suggested_office']) ?><?php endif; ?></p>
        </div>
        <?php if (!empty($x['report']['id'])): ?>
          <a class="btn-review" href="case.php?id=<?= e($x['report']['id']) ?>"><?= e(t('Review', 'Suriin')) ?></a>
        <?php endif; ?>
      </article>
    <?php endforeach; ?>
  </div>
</section>
<?php endif; ?>

<!-- ---------- complaint register ---------- -->
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title"><?= e(t('Reports', 'Mga Ulat')) ?> (<span id="reports-count"><?= count($reports) ?></span>)</h2>

    <?php $atc = count($attention ?? []); ?>
    <a class="chip-filter<?= $view === 'attention' ? ' is-on' : '' ?>" id="attention-chip"
       href="?<?= e(http_build_query(array_filter(['view' => $view === 'attention' ? '' : 'attention', 'q' => $search, 'status' => $filter, 'category' => $category, 'month' => $month]))) ?>">
      <?= e(t('Needs attention', 'Kailangang asikasuhin')) ?>
      <span class="chip-num<?= $atc > 0 ? ' is-hot' : '' ?>" id="attention-count"><?= $atc ?></span>
    </a>

    <form class="panel-search" method="get">
      <?= nav_icon('search') ?>
      <input type="search" name="q" placeholder="<?= e(t('Search Here', 'Maghanap Dito')) ?>" value="<?= e($search) ?>">
      <input type="hidden" name="status" value="<?= e($filter) ?>">
      <input type="hidden" name="category" value="<?= e($category) ?>">
      <input type="hidden" name="month" value="<?= e($month) ?>">
      <input type="hidden" name="sort" value="<?= e($_GET['sort'] ?? 'newest') ?>">
    </form>

    <form class="panel-sort" method="get">
      <input type="hidden" name="q" value="<?= e($search) ?>">
      <label class="filter-option">
        <input type="month" name="month" value="<?= e($month) ?>"
               onchange="this.form.submit()" aria-label="<?= e(t('Filter by month', 'Salain ayon sa buwan')) ?>">
      </label>
      <label class="filter-option">
        <select name="category" onchange="this.form.submit()">
          <option value=""><?= e(t('All Categories', 'Lahat ng Kategorya')) ?></option>
          <?php foreach (CATEGORIES as $c): ?>
            <option value="<?= e($c) ?>" <?= $category === $c ? 'selected' : '' ?>>
              <?= e(category_label($c)) ?>
            </option>
          <?php endforeach; ?>
        </select>
      </label>
      <label class="filter-option">
        <select name="status" onchange="this.form.submit()">
          <option value=""><?= e(t('Filter Option', 'Salain')) ?></option>
          <?php foreach ([
              'under_review' => t('Under Review', 'Nirerepaso'),
              'in_progress'  => t('In Progress', 'Isinasagawa'),
              'resolved'     => t('Resolved/Completed', 'Nalutas/Nakumpleto'),
              'rejected'     => t('Rejected', 'Tinanggihan'),
          ] as $s => $lbl): ?>
            <option value="<?= e($s) ?>" <?= $filter === $s ? 'selected' : '' ?>>
              <?= e($lbl) ?>
            </option>
          <?php endforeach; ?>
        </select>
      </label>
    </form>
  </header>

  <div class="table-wrap">
    <table class="case-table">
      <thead>
        <tr>
          <th scope="col"><?= e(t('Resident Name', 'Pangalan ng Residente')) ?></th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('id', $sortCol, $sortDir)) ?>"><?= e(t('Complaint ID', 'ID ng Sumbong')) ?><?= sort_caret('id', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('category', $sortCol, $sortDir)) ?>"><?= e(t('Category', 'Kategorya')) ?><?= sort_caret('category', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('status', $sortCol, $sortDir)) ?>"><?= e(t('Status', 'Katayuan')) ?><?= sort_caret('status', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('date', $sortCol, $sortDir)) ?>"><?= e(t('Date', 'Petsa')) ?><?= sort_caret('date', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><span class="visually-hidden"><?= e(t('Action', 'Aksyon')) ?></span></th>
        </tr>
      </thead>
      <tbody id="reports-tbody">
        <?php if (!$reports): ?>
          <tr class="row-empty">
            <td colspan="6">
              <?= $search !== '' || $filter !== '' || $category !== '' || $month !== ''
                  ? e(t('No complaint matches that search.', 'Walang sumbong na tugma sa hinanap.'))
                  : e(t('No complaints have been filed yet.', 'Wala pang naisampang sumbong.')) ?>
            </td>
          </tr>
        <?php endif; ?>

        <?php foreach ($reports as $r): ?>
          <tr>
            <td>
              <?php if (!empty($r['is_anonymous'])): ?>
                <span class="anon"><?= e(t('Anonymous', 'Hindi nagpakilala')) ?></span>
              <?php else: ?>
                <?= e($r['resident']['full_name'] ?? t('Unknown', 'Hindi kilala')) ?>
              <?php endif; ?>
            </td>
            <td class="mono"><?= e($r['tracking_id']) ?></td>
            <td><?= e(category_label($r['category'])) ?><?php if (!empty($r['location_label'])): ?><small class="cell-sub"><?= e($r['location_label']) ?></small><?php endif; ?></td>
            <td>
              <span class="pill pill--<?= e(status_class($r['status'])) ?>">
                <?= e(status_label($r['status'])) ?>
              </span>
              <?php if (report_is_overdue($r)): ?>
                <span class="pill pill--escalated"><?= e(t('Overdue', 'Lampas na sa takdang oras')) ?></span>
              <?php endif; ?>
              <?php if (!empty($r['referred_to'])): ?>
                <span class="pill pill--escalated"><?= e(t('Escalated to ', 'In-escalate sa ')) . e($r['referred_to']) ?></span>
              <?php endif; ?>
              <?php if (!empty($r['resolution_submitted_at'])): ?>
                <span class="pill pill--pending"><?= e(t('Awaiting approval', 'Naghihintay ng pag-apruba')) ?></span>
              <?php endif; ?>
              <?php if (!empty($r['followed_up_at']) && !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected', 'cancelled'], true)): ?>
                <span class="pill pill--pending"><?= e(t('Followed up', 'Nag-follow up')) ?></span>
              <?php endif; ?>
              <?php if (($r['reopened_count'] ?? 0) > 0): ?>
                <span class="pill pill--pending"><?= e(t('Reopened', 'Binuksang muli')) ?> <?= (int) $r['reopened_count'] ?>&times;</span>
              <?php endif; ?>
              <?php if (!empty($r['appealed_at'])): ?>
                <span class="pill pill--pending" title="<?= e(t('Reinstated on appeal', 'Ibinalik dahil sa apela')) ?>"><?= e(t('Appealed', 'Inapela')) ?></span>
              <?php endif; ?>
            </td>
            <td><?= e(short_date($r['created_at'])) ?></td>
            <td class="cell-action">
              <a class="btn-review" href="case.php?id=<?= e($r['id']) ?>"><?= e(t('Review', 'Suriin')) ?></a>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</section>

<script src="assets/vendor/supabase/supabase.js"></script>
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
  const CATEGORY   = <?= json_encode($category) ?>;
  const MONTH_FROM = <?= json_encode($month !== '' ? (DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', new DateTimeZone('Asia/Manila')))->format(DateTimeInterface::ATOM) : null) ?>;
  const MONTH_TO   = <?= json_encode($month !== '' ? (DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', new DateTimeZone('Asia/Manila')))->modify('first day of next month')->format(DateTimeInterface::ATOM) : null) ?>;
  const SEARCH     = <?= json_encode($search) ?>;
  const N_SEARCH   = <?= json_encode($nSearch) ?>;
  const N_OLDEST   = <?= json_encode($nSort === 'oldest') ?>;
  const VIEW       = <?= json_encode($view) ?>;
  const STATUS_LABEL = <?= json_encode(status_labels(), JSON_UNESCAPED_UNICODE) ?>;

  function escapeHtml(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }
  const titleCase = s => String(s ?? '').replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
  function statusClass(s) {
    switch (s) {
      case 'pending_review': return 'pending';
      case 'validated': return 'validated';
      case 'assigned': return 'assigned';
      case 'in_progress':
      case 'offline_investigation': return 'progress';
      case 'resolved': return 'resolved';
      case 'closed':
      case 'archived': return 'closed';
      case 'rejected': return 'rejected';
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

  function renderReports(all) {
    const filtered = VIEW === 'attention' ? all.filter(isAttention) : all;
    document.getElementById('reports-count').textContent = filtered.length;
    document.getElementById('attention-count').textContent =
      all.filter(isAttention).length;

    const tbody = document.getElementById('reports-tbody');
    if (!filtered.length) {
      tbody.innerHTML = '<tr class="row-empty"><td colspan="6">' +
        (SEARCH || STATUS || CATEGORY || MONTH_FROM ? T('No complaint matches that search.', 'Walang sumbong na tugma sa hinanap.')
                                                    : T('No complaints have been filed yet.', 'Wala pang naisampang sumbong.')) +
        '</td></tr>';
      return;
    }
    tbody.innerHTML = filtered.map(r => {
      const who = r.is_anonymous
        ? '<span class="anon">' + T('Anonymous', 'Hindi nagpakilala') + '</span>'
        : escapeHtml((r.resident && r.resident.full_name) || T('Unknown', 'Hindi kilala'));
      // 0072: Overdue (the admin's date has passed) replaces Escalated;
      // escalation is now a referral, shown by name.
      const open = !['resolved', 'closed', 'archived', 'rejected', 'cancelled'].includes(r.status);
      const escalated =
        (open && r.due_at && new Date(r.due_at) < new Date()
          ? '<span class="pill pill--escalated">' + T('Overdue', 'Lampas na sa takdang oras') + '</span>' : '') +
        (r.referred_to
          ? '<span class="pill pill--escalated">' + T('Escalated to ', 'In-escalate sa ') + escapeHtml(r.referred_to) + '</span>' : '') +
        (r.resolution_submitted_at
          ? '<span class="pill pill--pending">' + T('Awaiting approval', 'Naghihintay ng pag-apruba') + '</span>' : '') +
        (open && r.followed_up_at
          ? '<span class="pill pill--pending">' + T('Followed up', 'Nag-follow up') + '</span>' : '');
      const reopened = (r.reopened_count || 0) > 0
        ? '<span class="pill pill--pending">' + T('Reopened ', 'Binuksang muli ') + r.reopened_count + '&times;</span>' : '';
      const appealed = r.appealed_at
        ? '<span class="pill pill--pending" title="' + T('Reinstated on appeal', 'Ibinalik dahil sa apela') + '">' + T('Appealed', 'Inapela') + '</span>' : '';
      return '<tr>' +
        '<td>' + who + '</td>' +
        '<td class="mono">' + escapeHtml(r.tracking_id) + '</td>' +
        '<td>' + escapeHtml(titleCase(r.category)) +
          (r.location_label ? '<small class="cell-sub">' + escapeHtml(r.location_label) + '</small>' : '') + '</td>' +
        '<td><span class="pill pill--' + statusClass(r.status) + '">' +
          escapeHtml(STATUS_LABEL[r.status] || titleCase(r.status)) + '</span>' + escalated + reopened + appealed + '</td>' +
        '<td>' + shortDate(r.created_at) + '</td>' +
        '<td class="cell-action"><a class="btn-review" href="case.php?id=' +
          encodeURIComponent(r.id) + '">' + T('Review', 'Suriin') + '</a></td>' +
        '</tr>';
    }).join('');
  }

  function renderNotifications(rows) {
    document.getElementById('notif-count').textContent = rows.length;
    const list = document.getElementById('notif-list');
    if (!rows.length) {
      list.innerHTML = '<p class="empty" id="notif-empty">' + (N_SEARCH
        ? T('No notification matches that search.', 'Walang abisong tugma sa hinanap.')
        : T('Nothing new. Notifications appear here when a report is escalated, a deadline is missed, or a tanod files a resolution.',
            'Walang bago. Lalabas dito ang abiso kapag may ulat na na-escalate, may lumampas sa takdang oras, o may tanod na nagsumite ng resolusyon.')) + '</p>';
      return;
    }
    list.innerHTML = rows.map(n => {
      const review = n.report_id
        ? '<a class="btn-review" href="case.php?id=' + encodeURIComponent(n.report_id) + '">' + T('Review', 'Suriin') + '</a>' : '';
      return '<article class="notif">' +
        '<span class="notif-dot" aria-hidden="true"></span>' +
        '<div class="notif-body"><p class="notif-msg">' + escapeHtml(n.message) + '</p>' +
        '<p class="notif-when">' + escapeHtml(relativeTime(n.created_at)) + '</p></div>' +
        review + '</article>';
    }).join('');
  }

  async function loadReports() {
    let q = sb.from('reports')
      .select('id,tracking_id,subject,category,status,created_at,is_anonymous,location_label,'
        + 'due_at,awaiting_unit_since,reopened_count,appealed_at,referred_to,followed_up_at,resolution_submitted_at,'
        + 'resident:users!reports_resident_id_fkey(full_name)')
      .is('deleted_at', null)
      .order(SORT_COL, { ascending: SORT_ASC })
      .limit(100);
    if (STATUS) q = q.in('status', STATUS_GROUPS[STATUS] || [STATUS]);
    if (CATEGORY) q = q.eq('category', CATEGORY);
    if (MONTH_FROM) q = q.gte('created_at', MONTH_FROM).lt('created_at', MONTH_TO);
    if (SEARCH) {
      const needle = SEARCH.replace(/[,()"\\*]/g, ' ');   // mirrors the PHP above
      q = q.or('tracking_id.ilike.*' + needle + '*,subject.ilike.*' + needle + '*');
    }
    const { data, error } = await q;
    if (error) return; // stale view is safer than a half-rendered one
    renderReports(data || []);
  }

  async function loadNotifications() {
    let nq = sb.from('notifications')
      .select('id,kind,message,created_at,is_read,report_id')
      .eq('user_id', ADMIN_ID)
      .order('created_at', { ascending: N_OLDEST })
      .limit(N_SEARCH ? 50 : 20);
    // Same rule as the PHP above: a search includes read notifications.
    nq = N_SEARCH ? nq.ilike('message', '*' + N_SEARCH.replace(/[,()"\\*]/g, ' ') + '*')
                  : nq.eq('is_read', false);
    const { data, error } = await nq;
    if (error) return;
    renderNotifications(data || []);
  }

  // Bursts (a batch import, several tanods updating at once) collapse into
  // one refetch instead of one per row.
  const debounced = (fn, timerRef) => () => {
    clearTimeout(timerRef.id);
    timerRef.id = setTimeout(fn, 250);
  };
  const kickReports = debounced(loadReports, { id: null });
  const kickNotifs  = debounced(loadNotifications, { id: null });

  let wasDown = false;
  sb.channel('cases-list')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' }, kickReports)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications',
                               filter: 'user_id=eq.' + ADMIN_ID }, kickNotifs)
    .subscribe(status => {
      const badge = document.getElementById('live-badge'),
            text  = document.getElementById('live-badge-text');
      if (status === 'SUBSCRIBED') {
        badge.classList.remove('is-down'); text.textContent = T('Live', 'Live');
        // Nothing is replayed for the time the socket was down.
        if (wasDown) { wasDown = false; kickReports(); kickNotifs(); }
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        wasDown = true;
        badge.classList.add('is-down'); text.textContent = T('Reconnecting…', 'Kumokonekta muli…');
      }
    });
})();
</script>

<?php layout_foot(); ?>
