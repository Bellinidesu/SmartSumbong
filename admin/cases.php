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

$search   = trim((string) ($_GET['q'] ?? ''));
$filter   = (string) ($_GET['status'] ?? '');
$category = (string) ($_GET['category'] ?? '');
$month    = (string) ($_GET['month'] ?? '');
$view     = (string) ($_GET['view'] ?? '');

if (!in_array($category, CATEGORIES, true)) { $category = ''; }
if (!preg_match('/^\d{4}-\d{2}$/', $month)) { $month = ''; }

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

try {
    // The embedded resident is a PostgREST foreign-key expansion; the
    // join happens in the database, not in a second round trip.
    $query = [
        'select' => 'id,tracking_id,subject,category,status,created_at,is_anonymous,'
                  . 'escalation_level,due_at,awaiting_unit_since,reopened_count,appealed_at,'
                  . 'resident:users!reports_resident_id_fkey(full_name)',
        'deleted_at' => 'is.null',
        'order'      => $sort,
        'limit'      => '100',
    ];
    if ($filter !== '') {
        $query['status'] = 'eq.' . $filter;
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
        // Match either the tracking id or the subject line.
        $needle = str_replace(',', ' ', $search);
        $query['or'] = "(tracking_id.ilike.*{$needle}*,subject.ilike.*{$needle}*)";
    }
    $reports = $db->select('reports', $query);

    // "Needs attention" is the question an admin actually opens this page
    // with: what is late, what nobody has picked up, and what is still
    // sitting unreviewed. Three separate conditions, one chip.
    $attention = array_values(array_filter($reports, function (array $r) {
        $open    = !in_array($r['status'], ['resolved', 'closed', 'archived', 'rejected'], true);
        $overdue = $open && !empty($r['due_at']) && strtotime($r['due_at']) < time();
        return $overdue
            || !empty($r['awaiting_unit_since'])
            || $r['status'] === 'pending_review';
    }));
    if ($view === 'attention') { $reports = $attention; }

    $notifications = $db->select('notifications', [
        'select'  => 'id,kind,message,created_at,is_read,report_id',
        'user_id' => 'eq.' . $admin['id'],
        'is_read' => 'is.false',
        'order'   => 'created_at.desc',
        'limit'   => '20',
    ]);
} catch (SupabaseError $ex) {
    $error = safe_error($ex);
}

layout_head('Case Reports', 'cases.php');
?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
<?php endif; ?>

<!-- ---------- notifications ---------- -->
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title">Notification (<span id="notif-count"><?= count($notifications) ?></span>)
      <span class="live-badge" id="live-badge" title="Updates as they happen — no reload needed">
        <span class="live-dot" aria-hidden="true"></span><span id="live-badge-text">Live</span>
      </span>
    </h2>
    <form class="panel-search" method="get">
      <?= nav_icon('search') ?>
      <input type="search" name="nq" placeholder="Search Here" value="<?= e($_GET['nq'] ?? '') ?>">
    </form>
    <div class="panel-sort">Sort by: <strong>Unread</strong></div>
  </header>

  <div class="notif-list" id="notif-list">
    <?php if (!$notifications): ?>
      <p class="empty" id="notif-empty">Nothing new. Notifications appear here when a report is
         escalated, a deadline is missed, or a tanod files a resolution.</p>
    <?php endif; ?>

    <?php foreach ($notifications as $n): ?>
      <article class="notif">
        <span class="notif-dot" aria-hidden="true"></span>
        <div class="notif-body">
          <p class="notif-msg"><?= e($n['message']) ?></p>
          <p class="notif-when"><?= e(relative_time($n['created_at'])) ?></p>
        </div>
        <?php if (!empty($n['report_id'])): ?>
          <a class="btn-review" href="case.php?id=<?= e($n['report_id']) ?>">Review</a>
        <?php endif; ?>
      </article>
    <?php endforeach; ?>
  </div>
</section>

<!-- ---------- complaint register ---------- -->
<section class="panel">
  <header class="panel-bar">
    <h2 class="panel-title">Reports (<span id="reports-count"><?= count($reports) ?></span>)</h2>

    <?php $atc = count($attention ?? []); ?>
    <a class="chip-filter<?= $view === 'attention' ? ' is-on' : '' ?>" id="attention-chip"
       href="?<?= e(http_build_query(array_filter(['view' => $view === 'attention' ? '' : 'attention', 'q' => $search, 'status' => $filter, 'category' => $category, 'month' => $month]))) ?>">
      Needs attention
      <span class="chip-num<?= $atc > 0 ? ' is-hot' : '' ?>" id="attention-count"><?= $atc ?></span>
    </a>

    <form class="panel-search" method="get">
      <?= nav_icon('search') ?>
      <input type="search" name="q" placeholder="Search Here" value="<?= e($search) ?>">
      <input type="hidden" name="status" value="<?= e($filter) ?>">
      <input type="hidden" name="category" value="<?= e($category) ?>">
      <input type="hidden" name="month" value="<?= e($month) ?>">
      <input type="hidden" name="sort" value="<?= e($_GET['sort'] ?? 'newest') ?>">
    </form>

    <form class="panel-sort" method="get">
      <input type="hidden" name="q" value="<?= e($search) ?>">
      <label class="filter-option">
        <input type="month" name="month" value="<?= e($month) ?>"
               onchange="this.form.submit()" aria-label="Filter by month">
      </label>
      <label class="filter-option">
        <select name="category" onchange="this.form.submit()">
          <option value="">All Categories</option>
          <?php foreach (CATEGORIES as $c): ?>
            <option value="<?= e($c) ?>" <?= $category === $c ? 'selected' : '' ?>>
              <?= e(category_label($c)) ?>
            </option>
          <?php endforeach; ?>
        </select>
      </label>
      <label class="filter-option">
        <select name="status" onchange="this.form.submit()">
          <option value="">Filter Option</option>
          <?php foreach ([
              'pending_review', 'validated', 'assigned', 'in_progress',
              'offline_investigation', 'resolved', 'closed', 'rejected',
          ] as $s): ?>
            <option value="<?= e($s) ?>" <?= $filter === $s ? 'selected' : '' ?>>
              <?= e(status_label($s)) ?>
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
          <th scope="col">Resident Name</th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('id', $sortCol, $sortDir)) ?>">Complaint ID<?= sort_caret('id', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('category', $sortCol, $sortDir)) ?>">Category<?= sort_caret('category', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('status', $sortCol, $sortDir)) ?>">Status<?= sort_caret('status', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><a class="th-sort" href="<?= e(sort_link('date', $sortCol, $sortDir)) ?>">Date<?= sort_caret('date', $sortCol, $sortDir) ?></a></th>
          <th scope="col"><span class="visually-hidden">Action</span></th>
        </tr>
      </thead>
      <tbody id="reports-tbody">
        <?php if (!$reports): ?>
          <tr class="row-empty">
            <td colspan="6">
              <?= $search !== '' || $filter !== '' || $category !== '' || $month !== ''
                  ? 'No complaint matches that search.'
                  : 'No complaints have been filed yet.' ?>
            </td>
          </tr>
        <?php endif; ?>

        <?php foreach ($reports as $r): ?>
          <tr>
            <td>
              <?php if (!empty($r['is_anonymous'])): ?>
                <span class="anon">Anonymous</span>
              <?php else: ?>
                <?= e($r['resident']['full_name'] ?? 'Unknown') ?>
              <?php endif; ?>
            </td>
            <td class="mono"><?= e($r['tracking_id']) ?></td>
            <td><?= e(category_label($r['category'])) ?></td>
            <td>
              <span class="pill pill--<?= e(status_class($r['status'])) ?>">
                <?= e(status_label($r['status'])) ?>
              </span>
              <?php if (($r['escalation_level'] ?? 0) > 0): ?>
                <span class="pill pill--escalated" title="Escalated">Escalated</span>
              <?php endif; ?>
              <?php if (($r['reopened_count'] ?? 0) > 0): ?>
                <span class="pill pill--pending">Reopened <?= (int) $r['reopened_count'] ?>&times;</span>
              <?php endif; ?>
              <?php if (!empty($r['appealed_at'])): ?>
                <span class="pill pill--pending" title="Reinstated on appeal">Appealed</span>
              <?php endif; ?>
            </td>
            <td><?= e(short_date($r['created_at'])) ?></td>
            <td class="cell-action">
              <a class="btn-review" href="case.php?id=<?= e($r['id']) ?>">Review</a>
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
    { global: { headers: { Authorization: 'Bearer ' + TOKEN } },
      auth: { persistSession: false, autoRefreshToken: false } }
  );
  sb.realtime.setAuth(TOKEN);

  // The view this page loaded with. Realtime keeps re-querying against
  // this exact filter/sort/search, so a new complaint appears live only
  // where it would actually belong once the page is reloaded too — it
  // never silently changes what the admin is looking at.
  const SORT_COL   = <?= json_encode($SORTABLE[$sortCol]) ?>;
  const SORT_ASC   = <?= json_encode($sortDir === 'asc') ?>;
  const STATUS     = <?= json_encode($filter) ?>;
  const CATEGORY   = <?= json_encode($category) ?>;
  const MONTH_FROM = <?= json_encode($month !== '' ? (DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', new DateTimeZone('Asia/Manila')))->format(DateTimeInterface::ATOM) : null) ?>;
  const MONTH_TO   = <?= json_encode($month !== '' ? (DateTimeImmutable::createFromFormat('!Y-m-d', $month . '-01', new DateTimeZone('Asia/Manila')))->modify('first day of next month')->format(DateTimeInterface::ATOM) : null) ?>;
  const SEARCH     = <?= json_encode($search) ?>;
  const VIEW       = <?= json_encode($view) ?>;

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
    if (mins < 1) return 'Just now';
    if (mins < 60) return mins + ' min ago';
    if (mins < 1440) return Math.floor(mins / 60) + ' hr ago';
    return new Intl.DateTimeFormat('en-US',
      { timeZone: 'Asia/Manila', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
      .format(new Date(iso));
  }
  function isAttention(r) {
    const open = !['resolved', 'closed', 'archived', 'rejected'].includes(r.status);
    const overdue = open && r.due_at && new Date(r.due_at).getTime() < Date.now();
    return overdue || !!r.awaiting_unit_since || r.status === 'pending_review';
  }

  function renderReports(all) {
    const filtered = VIEW === 'attention' ? all.filter(isAttention) : all;
    document.getElementById('reports-count').textContent = filtered.length;
    document.getElementById('attention-count').textContent =
      all.filter(isAttention).length;

    const tbody = document.getElementById('reports-tbody');
    if (!filtered.length) {
      tbody.innerHTML = '<tr class="row-empty"><td colspan="6">' +
        (SEARCH || STATUS || CATEGORY || MONTH_FROM ? 'No complaint matches that search.' : 'No complaints have been filed yet.') +
        '</td></tr>';
      return;
    }
    tbody.innerHTML = filtered.map(r => {
      const who = r.is_anonymous
        ? '<span class="anon">Anonymous</span>'
        : escapeHtml((r.resident && r.resident.full_name) || 'Unknown');
      const escalated = (r.escalation_level || 0) > 0
        ? '<span class="pill pill--escalated" title="Escalated">Escalated</span>' : '';
      const reopened = (r.reopened_count || 0) > 0
        ? '<span class="pill pill--pending">Reopened ' + r.reopened_count + '&times;</span>' : '';
      const appealed = r.appealed_at
        ? '<span class="pill pill--pending" title="Reinstated on appeal">Appealed</span>' : '';
      return '<tr>' +
        '<td>' + who + '</td>' +
        '<td class="mono">' + escapeHtml(r.tracking_id) + '</td>' +
        '<td>' + escapeHtml(titleCase(r.category)) + '</td>' +
        '<td><span class="pill pill--' + statusClass(r.status) + '">' +
          escapeHtml(titleCase(r.status)) + '</span>' + escalated + reopened + appealed + '</td>' +
        '<td>' + shortDate(r.created_at) + '</td>' +
        '<td class="cell-action"><a class="btn-review" href="case.php?id=' +
          encodeURIComponent(r.id) + '">Review</a></td>' +
        '</tr>';
    }).join('');
  }

  function renderNotifications(rows) {
    document.getElementById('notif-count').textContent = rows.length;
    const list = document.getElementById('notif-list');
    if (!rows.length) {
      list.innerHTML = '<p class="empty" id="notif-empty">Nothing new. Notifications appear here when a report is' +
        ' escalated, a deadline is missed, or a tanod files a resolution.</p>';
      return;
    }
    list.innerHTML = rows.map(n => {
      const review = n.report_id
        ? '<a class="btn-review" href="case.php?id=' + encodeURIComponent(n.report_id) + '">Review</a>' : '';
      return '<article class="notif">' +
        '<span class="notif-dot" aria-hidden="true"></span>' +
        '<div class="notif-body"><p class="notif-msg">' + escapeHtml(n.message) + '</p>' +
        '<p class="notif-when">' + escapeHtml(relativeTime(n.created_at)) + '</p></div>' +
        review + '</article>';
    }).join('');
  }

  async function loadReports() {
    let q = sb.from('reports')
      .select('id,tracking_id,subject,category,status,created_at,is_anonymous,'
        + 'escalation_level,due_at,awaiting_unit_since,reopened_count,appealed_at,'
        + 'resident:users!reports_resident_id_fkey(full_name)')
      .is('deleted_at', null)
      .order(SORT_COL, { ascending: SORT_ASC })
      .limit(100);
    if (STATUS) q = q.eq('status', STATUS);
    if (CATEGORY) q = q.eq('category', CATEGORY);
    if (MONTH_FROM) q = q.gte('created_at', MONTH_FROM).lt('created_at', MONTH_TO);
    if (SEARCH) {
      const needle = SEARCH.replace(/,/g, ' ');
      q = q.or('tracking_id.ilike.*' + needle + '*,subject.ilike.*' + needle + '*');
    }
    const { data, error } = await q;
    if (error) return; // stale view is safer than a half-rendered one
    renderReports(data || []);
  }

  async function loadNotifications() {
    const { data, error } = await sb.from('notifications')
      .select('id,kind,message,created_at,is_read,report_id')
      .eq('user_id', ADMIN_ID)
      .eq('is_read', false)
      .order('created_at', { ascending: false })
      .limit(20);
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

  sb.channel('cases-list')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'reports' }, kickReports)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications',
                               filter: 'user_id=eq.' + ADMIN_ID }, kickNotifs)
    .subscribe(status => {
      const badge = document.getElementById('live-badge'),
            text  = document.getElementById('live-badge-text');
      if (status === 'SUBSCRIBED') {
        badge.classList.remove('is-down'); text.textContent = 'Live';
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        badge.classList.add('is-down'); text.textContent = 'Reconnecting…';
      }
    });
})();
</script>

<?php layout_foot(); ?>
