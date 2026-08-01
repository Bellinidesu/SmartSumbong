<?php
/**
 * Case detail — Figma nodes 2:2526 (Case review) and 36:1202 (Case Assign).
 *
 * One page, not two. The two frames are the same screen at two points in
 * a complaint's life: while it is pending_review the Admin Controls panel
 * offers Accept and Deny, and once it is validated the same panel becomes
 * the tanod roster with a note, a target date and Dispatch. Splitting them
 * into separate files would mean duplicating the complaint card, the
 * timeline and the map three times over.
 *
 * Every state change goes through a database function, never a bare
 * UPDATE, so the status, the audit trail and the resident's notification
 * move together or not at all.
 */
declare(strict_types=1);

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/layout.php';

$admin = require_admin();
$db    = db();

$id = (string) ($_GET['id'] ?? '');
if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $id)) {
    header('Location: cases.php');
    exit;
}

session_start_once();

// ---------- actions ----------
// Post-redirect-get: a refresh after accepting must not accept again.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $flash = null;
    $level = 'ok';

    if (!csrf_check($_POST['csrf'] ?? null)) {
        $flash = 'That form expired. Please try again.';
        $level = 'error';
    } else {
        try {
            switch ($_POST['action'] ?? '') {
                case 'accept':
                    $db->rpc('review_report', [
                        'p_report'   => $id,
                        'p_decision' => 'validate',
                    ]);
                    $flash = 'Complaint accepted. Assign a tanod when you are ready.';
                    break;

                case 'deny':
                    $db->rpc('review_report', [
                        'p_report'   => $id,
                        'p_decision' => 'reject',
                        'p_remark'   => trim((string) ($_POST['reason'] ?? '')),
                    ]);
                    $flash = 'Complaint denied. The resident has been told why.';
                    break;

                case 'dispatch':
                    $tanod = trim((string) ($_POST['tanod'] ?? ''));
                    if ($tanod === '') {
                        throw new SupabaseError('Choose a tanod before dispatching.');
                    }

                    // The target date is optional, and it is set before the
                    // dispatch so the tanod's ticket carries the deadline the
                    // admin meant rather than the policy default.
                    $target = trim((string) ($_POST['target'] ?? ''));
                    if ($target !== '') {
                        $iso = (new DateTimeImmutable($target, new DateTimeZone('Asia/Manila')))
                            ->format(DateTimeInterface::ATOM);
                        $db->rpc('set_resolution_target', [
                            'p_report' => $id,
                            'p_due'    => $iso,
                        ]);
                    }

                    $db->rpc('admin_dispatch', [
                        'p_report'       => $id,
                        'p_tanod'        => $tanod,
                        'p_instructions' => trim((string) ($_POST['note'] ?? '')) ?: null,
                    ]);
                    $flash = 'Dispatched. The tanod has been notified.';
                    break;

                default:
                    $flash = 'Unknown action.';
                    $level = 'error';
            }
        } catch (SupabaseError $ex) {
            $flash = $ex->getMessage();
            $level = 'error';
        } catch (Exception $ex) {
            $flash = 'That date could not be read. Use the date picker.';
            $level = 'error';
        }
    }

    $_SESSION['flash'] = ['text' => $flash, 'level' => $level];
    header('Location: case.php?id=' . urlencode($id));
    exit;
}

$flash = $_SESSION['flash'] ?? null;
unset($_SESSION['flash']);

// ---------- data ----------
$error = null;
$report = null;
$media = $logs = $dispatches = $roster = [];
$policy = null;

try {
    $rows = $db->select('reports', [
        'select' => 'id,tracking_id,subject,description,category,status,is_anonymous,'
                  . 'latitude,longitude,due_at,escalated_at,escalation_level,reopened_count,'
                  . 'awaiting_unit_since,dispatch_attempts,resolved_at,closed_at,created_at,'
                  . 'resident:users!reports_resident_id_fkey(id,full_name,mobile_number)',
        'id'         => 'eq.' . $id,
        'deleted_at' => 'is.null',
        'limit'      => '1',
    ]);
    $report = $rows[0] ?? null;

    if ($report) {
        $media = $db->select('report_media', [
            'select'    => 'id,media_url,mime_type,bytes,uploaded_at',
            'report_id' => 'eq.' . $id,
            'order'     => 'uploaded_at.asc',
        ]);

        $logs = $db->select('status_logs', [
            'select'    => 'id,old_status,new_status,remark,is_system,created_at,'
                         . 'by:users!status_logs_changed_by_fkey(full_name,role)',
            'report_id' => 'eq.' . $id,
            'order'     => 'created_at.asc',
        ]);

        $dispatches = $db->select('dispatches', [
            'select'    => 'id,state,assigned_at,accept_due_at,accepted_at,admin_instructions,'
                         . 'rerouted_at,reroute_reason,field_report_text,resolved_at,'
                         . 'tanod:users!dispatches_tanod_id_fkey(id,full_name,mobile_number)',
            'report_id' => 'eq.' . $id,
            'order'     => 'assigned_at.desc',
        ]);

        $sla = $db->select('sla_policies', [
            'select'   => 'resolution_hours,accept_minutes,auto_dispatch_on_file',
            'category' => 'eq.' . $report['category'],
            'limit'    => '1',
        ]);
        $policy = $sla[0] ?? null;
    }
} catch (SupabaseError $ex) {
    $error = $ex->getMessage();
}

if (!$report && !$error) {
    $error = 'That complaint could not be found. It may have been archived.';
}

/** The dispatch that is currently live, if any. */
$active = null;
foreach ($dispatches as $d) {
    if (in_array($d['state'], ['assigned', 'accepted'], true)) {
        $active = $d;
        break;
    }
}

$status   = $report['status'] ?? '';
$canJudge = $status === 'pending_review';
$canAssign = in_array($status, ['validated', 'in_progress', 'offline_investigation'], true)
             && $active === null;

// Fetched last because it depends on knowing there is nobody on the case
// already. One round trip saved on every screen that will not show it.
if ($canAssign && !$error) {
    try {
        $roster = $db->rpc('tanod_roster', ['p_report' => $id]);
    } catch (SupabaseError $ex) {
        $error = $ex->getMessage();
    }
}

layout_head('Case Review', 'cases.php');
?>

<?php if ($flash): ?>
  <div class="flash flash--<?= e($flash['level']) ?>" role="status"><?= e($flash['text']) ?></div>
<?php endif; ?>

<?php if ($error): ?>
  <div class="alert-bar" role="alert"><?= e($error) ?></div>
  <p><a class="back-link" href="cases.php">&larr; Back to case reports</a></p>
  <?php layout_foot(); exit; ?>
<?php endif; ?>

<div class="case-top">
  <a class="back-link" href="cases.php" aria-label="Back to case reports">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <line x1="20" y1="12" x2="5" y2="12"/><polyline points="11 18 5 12 11 6"/>
    </svg>
  </a>
  <span class="chip-tab">Original Report</span>
</div>

<div class="case-grid<?= $canAssign ? ' case-grid--assign' : '' ?>">

  <!-- ---------- the complaint itself ---------- -->
  <section class="card card--complaint">
    <h1 class="case-heading">
      <?= e($report['tracking_id']) ?>: <?= e(category_label($report['category'])) ?>
    </h1>

    <p class="case-filed">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
           stroke-linecap="round" aria-hidden="true">
        <circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 14"/>
      </svg>
      Filed on <?= e(long_datetime($report['created_at'])) ?>
    </p>

    <div class="case-flags">
      <span class="pill pill--<?= e(status_class($status)) ?>"><?= e(status_label($status)) ?></span>
      <?php if (($report['escalation_level'] ?? 0) > 0): ?>
        <span class="pill pill--escalated">Escalated (level <?= (int) $report['escalation_level'] ?>)</span>
      <?php endif; ?>
      <?php if (!empty($report['awaiting_unit_since'])): ?>
        <span class="pill pill--rejected">Awaiting a unit since <?= e(relative_time($report['awaiting_unit_since'])) ?></span>
      <?php endif; ?>
      <?php if (($report['reopened_count'] ?? 0) > 0): ?>
        <span class="pill pill--pending">Reopened <?= (int) $report['reopened_count'] ?>&times;</span>
      <?php endif; ?>
    </div>

    <div class="case-block">
      <h3 class="case-sub">Subject</h3>
      <p class="case-body"><?= e($report['subject']) ?></p>
    </div>

    <div class="case-block">
      <h3 class="case-sub">Problem Description</h3>
      <p class="case-body"><?= nl2br(e($report['description'])) ?></p>
    </div>

    <div class="case-block">
      <h3 class="case-sub">Attached Photo</h3>
      <?php if (!$media): ?>
        <p class="case-none">No photo was attached to this complaint.</p>
      <?php else: ?>
        <div class="media-strip">
          <?php foreach ($media as $m): ?>
            <a class="media-thumb" href="<?= e($m['media_url']) ?>" target="_blank" rel="noopener">
              <img src="<?= e($m['media_url']) ?>" alt="Evidence submitted with <?= e($report['tracking_id']) ?>" loading="lazy">
              <span class="media-size"><?= e(byte_size((int) $m['bytes'])) ?></span>
            </a>
          <?php endforeach; ?>
        </div>
      <?php endif; ?>
    </div>
  </section>

  <!-- ---------- admin controls ---------- -->
  <aside class="card card--controls">
    <h3 class="case-sub">Admin Controls</h3>

    <?php if ($canJudge): ?>
      <form method="post" class="control-stack" id="review-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <button class="btn-accept" type="submit" name="action" value="accept">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
               stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <polyline points="20 6 9 17 4 12"/>
          </svg>
          Accept Complaint
        </button>

        <button class="btn-deny" type="button" id="deny-toggle" aria-expanded="false"
                aria-controls="deny-panel">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
               stroke-linecap="round" aria-hidden="true"><line x1="5" y1="12" x2="19" y2="12"/></svg>
          Deny Complaint
        </button>

        <div class="deny-panel" id="deny-panel" hidden>
          <label for="reason" class="field-label">
            Reason for denial &mdash; the resident sees this
          </label>
          <textarea id="reason" name="reason" rows="3" maxlength="200" required
                    placeholder="e.g. Outside barangay jurisdiction — refer to the city ENRO."></textarea>
          <button class="btn-deny-confirm" type="submit" name="action" value="deny">
            Confirm denial
          </button>
        </div>
      </form>

    <?php elseif ($canAssign): ?>
      <form method="post" class="control-stack" id="assign-form">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">

        <p class="roster-head">Assign Tanod</p>

        <?php if (!$roster): ?>
          <p class="case-none">No tanod accounts exist yet. Add them under Personnel.</p>
        <?php endif; ?>

        <div class="roster">
          <?php foreach ($roster as $i => $t): ?>
            <?php $ok = !empty($t['assignable']); ?>
            <label class="roster-row<?= $ok ? '' : ' is-out' ?>">
              <input type="radio" name="tanod" value="<?= e($t['tanod_id']) ?>"
                     <?= $ok ? '' : 'disabled' ?>>
              <span class="roster-name">
                <?= e($t['full_name']) ?>
                <?php if ($ok && $t['metres'] !== null): ?>
                  <small class="roster-dist<?= empty($t['location_fresh']) ? ' is-stale' : '' ?>">
                    <?= e(distance_label((float) $t['metres'])) ?> away<?php
                      if (empty($t['location_fresh'])) echo ', last seen a while ago'; ?>
                  </small>
                <?php endif; ?>
              </span>
              <span class="roster-state <?= $ok ? 'is-on' : 'is-off' ?>">
                <?= $ok ? 'ONLINE' : e(strtoupper((string) ($t['unavailable_why'] ?? 'OFFLINE'))) ?>
              </span>
              <span class="roster-pick"><?= $ok ? 'Assign' : '&mdash;' ?></span>
            </label>
          <?php endforeach; ?>
        </div>

        <div class="control-field">
          <label class="field-label" for="note">Add Note</label>
          <textarea id="note" name="note" rows="2" maxlength="500"
                    placeholder="Instructions for the tanod on the ground."></textarea>
        </div>

        <div class="control-field">
          <label class="field-label" for="target">Target date resolution</label>
          <input type="datetime-local" id="target" name="target"
                 value="<?= e(local_input_value($report['due_at'])) ?>">
          <p class="field-hint">
            <?php if ($policy): ?>
              Policy for <?= e(category_label($report['category'])) ?> is
              <?= (int) $policy['resolution_hours'] ?> hours from filing.
            <?php endif; ?>
            <?php if (!empty($report['due_at'])): ?>
              Currently due <?= e(long_datetime($report['due_at'])) ?>.
            <?php endif; ?>
          </p>
        </div>

        <button class="btn-dispatch" type="submit" name="action" value="dispatch">Dispatch</button>
      </form>

    <?php else: ?>
      <?php if ($active): ?>
        <div class="assigned-card">
          <p class="assigned-label">Currently with</p>
          <p class="assigned-name"><?= e($active['tanod']['full_name'] ?? 'Unknown tanod') ?></p>
          <p class="assigned-meta">
            <?= e(status_label($active['state'])) ?>
            &middot; assigned <?= e(relative_time($active['assigned_at'])) ?>
          </p>
          <?php if ($active['state'] === 'assigned' && !empty($active['accept_due_at'])): ?>
            <p class="assigned-meta">
              Must accept by <?= e(long_datetime($active['accept_due_at'])) ?>
            </p>
          <?php endif; ?>
          <?php if (!empty($active['admin_instructions'])): ?>
            <p class="assigned-note"><?= e($active['admin_instructions']) ?></p>
          <?php endif; ?>
        </div>
      <?php else: ?>
        <p class="case-none">
          <?= $status === 'rejected'
              ? 'This complaint was denied. Nothing further is required.'
              : 'No action is available at this stage.' ?>
        </p>
      <?php endif; ?>

      <?php if (!empty($report['due_at'])): ?>
        <p class="due-line">Resolution target: <strong><?= e(long_datetime($report['due_at'])) ?></strong></p>
      <?php endif; ?>
    <?php endif; ?>

    <!-- ---------- map preview ---------- -->
    <div class="map-preview">
      <div id="case-map"></div>
      <span class="map-label"><?= e(coord_label((float) $report['latitude'], (float) $report['longitude'])) ?></span>
    </div>
  </aside>

  <!-- ---------- the register row, as designed ---------- -->
  <div class="case-strip">
    <span><?= !empty($report['is_anonymous'])
              ? '<em class="anon">Anonymous</em>'
              : e($report['resident']['full_name'] ?? 'Unknown') ?></span>
    <span class="mono"><?= e($report['tracking_id']) ?></span>
    <span><?= e(category_label($report['category'])) ?></span>
    <span><?= e(short_date($report['created_at'])) ?></span>
  </div>

  <!-- ---------- timeline ---------- -->
  <section class="card card--timeline">
    <h3 class="case-sub">Activity Timeline</h3>

    <ol class="timeline">
      <?php foreach ($logs as $l): ?>
        <li class="tl-item">
          <span class="tl-dot" aria-hidden="true"></span>
          <p class="tl-title"><?= e(timeline_title($l)) ?></p>
          <p class="tl-when"><?= e(long_datetime($l['created_at'])) ?></p>
          <?php if (!empty($l['remark'])): ?>
            <p class="tl-remark"><?= e($l['remark']) ?></p>
          <?php endif; ?>
          <p class="tl-who">
            <?= !empty($l['is_system'])
                ? 'System'
                : e($l['by']['full_name'] ?? 'Barangay staff') ?>
          </p>
        </li>
      <?php endforeach; ?>

      <li class="tl-item tl-now">
        <span class="tl-dot tl-dot--now" aria-hidden="true"></span>
        <p class="tl-when">Today &middot; <?= e((new DateTimeImmutable('now', new DateTimeZone('Asia/Manila')))->format('g:i A')) ?></p>
      </li>
    </ol>
  </section>
</div>

<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
(function () {
  // Deny is destructive and irreversible, so it asks for a reason before
  // it will submit. The button only reveals the field; the second one commits.
  var toggle = document.getElementById('deny-toggle');
  if (toggle) {
    var panel = document.getElementById('deny-panel');
    toggle.addEventListener('click', function () {
      var open = panel.hasAttribute('hidden');
      if (open) { panel.removeAttribute('hidden'); } else { panel.setAttribute('hidden', ''); }
      toggle.setAttribute('aria-expanded', String(open));
      if (open) { document.getElementById('reason').focus(); }
    });
  }

  // A preview, not a tool: no dragging, no zoom, no scroll hijack. The
  // full interactive map is Spatial Distribution.
  var el = document.getElementById('case-map');
  if (el && window.L) {
    var lat = <?= json_encode((float) $report['latitude']) ?>,
        lng = <?= json_encode((float) $report['longitude']) ?>;
    var map = L.map(el, {
      center: [lat, lng], zoom: 17,
      dragging: false, scrollWheelZoom: false, doubleClickZoom: false,
      zoomControl: false, keyboard: false, touchZoom: false, boxZoom: false
    });
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);
    L.marker([lat, lng]).addTo(map);
  }
})();
</script>

<?php layout_foot(); ?>
